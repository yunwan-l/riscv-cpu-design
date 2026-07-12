#!/usr/bin/env python3
"""
RVP Piano - PC 端可视化与音频播放

通过 UART 接收 FPGA 发来的音符数据，实时生成音频并显示波形。
FPGA 作为钢琴键盘（拨码开关选音），PC 作为合成器+示波器。

依赖安装:
  pip install pyserial numpy sounddevice matplotlib

用法:
  python pc_piano.py COM5        # 指定串口号
  python pc_piano.py             # 自动搜索串口

注意:
  - 运行前请先关闭 MobaXterm 的串口会话，否则串口被占用！
  - 关闭波形窗口即可退出程序。

操作:
  1. 在 Vivado 中完成 Synthesis -> Implementation -> Generate Bitstream
  2. Program Device 烧录到 Nexys4 DDR
  3. 运行本脚本，拨动板上的拨码开关演奏
  4. PC 上实时显示波形并通过扬声器播放声音
"""

import sys
import threading
import numpy as np

# ---- 依赖检查 ----
missing = []
try:
    import serial
except ImportError:
    missing.append('pyserial')
try:
    import sounddevice as sd
except ImportError:
    missing.append('sounddevice')
try:
    import matplotlib
    matplotlib.use('TkAgg')
    import matplotlib.pyplot as plt
    import matplotlib.animation as animation
    from matplotlib.patches import Rectangle
except ImportError:
    missing.append('matplotlib')

if missing:
    print("缺少依赖库，请先安装:")
    print(f"  pip install {' '.join(missing)}")
    sys.exit(1)

# ============================================================================
# 配置
# ============================================================================
SAMPLE_RATE    = 44100    # 音频采样率
BUFFER_SAMPLES = 1024     # 音频回调每次帧数
DISPLAY_SAMPLES = 2048    # 波形显示样本数

# 音符表: (名称, 频率Hz) — 与硬件 rvp_piano.sv 查表一致
NOTES = [
    ('C4', 262),  ('D4', 294),  ('E4', 330),  ('F4', 349),
    ('G4', 392),  ('A4', 440),  ('B4', 494),  ('C5', 523),
    ('D5', 587),  ('E5', 659),  ('F5', 698),  ('G5', 784),
    ('A5', 880),  ('B5', 988),  ('C6', 1047), ('D6', 1175),
]

# ============================================================================
# 共享状态（线程间）
# ============================================================================
current_note = 0          # 0=静音, 1-16=音符
audio_buffer = np.zeros(DISPLAY_SAMPLES, dtype=np.float32)
lock = threading.Lock()
phase = 0.0               # 相位累加器
# 包络状态
env_level = 0.0
env_target = 0.0

# UART 状态: "connecting" / "connected" / "error" / "disconnected"
uart_status = "connecting"
uart_error_msg = ""
uart_bytes_received = 0

# 全局引用，用于关闭时清理
_stream = None
_ser = None
_running = True

# ============================================================================
# UART 接收线程
# ============================================================================
def uart_receiver(port_name):
    global current_note, env_target, uart_status, uart_error_msg, uart_bytes_received, _ser, _running

    try:
        _ser = serial.Serial(port_name, 115200, timeout=0.1)
        uart_status = "connected"
        uart_error_msg = ""
        print(f"[UART] 已连接 {port_name} @ 115200 baud")
    except Exception as e:
        uart_status = "error"
        uart_error_msg = str(e)
        print(f"[UART] 无法打开串口 {port_name}: {e}")
        print("[UART] 可能原因：")
        print("  1. MobaXterm 正在占用该串口 -> 关闭 MobaXterm 串口会话")
        print("  2. COM 端口号不对 -> 打开设备管理器查看")
        print("  3. USB 线未连接")
        return

    while _running:
        try:
            data = _ser.read(1)
            if data:
                note = data[0]
                uart_bytes_received += 1
                if 0 <= note <= 16:
                    with lock:
                        current_note = note
                        env_target = 1.0 if note > 0 else 0.0
                    name = NOTES[note-1][0] if note > 0 else '---'
                    freq = NOTES[note-1][1] if note > 0 else 0
                    print(f"\r[NOTE] {name:>4s}  {freq:>5d} Hz  |  RX: {uart_bytes_received} bytes  ", end='', flush=True)
        except Exception as e:
            if _running:
                uart_status = "disconnected"
                uart_error_msg = str(e)
                print(f"\n[UART] 串口断开: {e}")
            break

    if _ser:
        _ser.close()

# ============================================================================
# 音频回调（由 sounddevice 在独立线程中调用）
# ============================================================================
def audio_callback(outdata, frames, time_info, status):
    global phase, env_level

    with lock:
        note = current_note
        target = env_target

    if note == 0:
        # 静音 — 用包络淡出避免爆音
        decay = np.exp(-np.arange(frames) / (SAMPLE_RATE * 0.02))
        outdata[:, 0] = audio_buffer[-frames:] * decay * 0.3
        env_level = max(0.0, env_level * decay[-1])
        # 更新显示缓冲
        audio_buffer[:-frames] = audio_buffer[frames:]
        audio_buffer[-frames:] = outdata[:, 0]
        return

    freq = NOTES[note - 1][1]
    t = np.arange(frames) / SAMPLE_RATE
    phase_arr = phase + 2 * np.pi * freq * t
    phase = phase_arr[-1] % (2 * np.pi)

    # 合成音色：方波基音 + 正弦谐波，模拟电子钢琴
    wave = np.sign(np.sin(phase_arr)) * 0.35
    wave += np.sin(phase_arr) * 0.25
    wave += np.sin(2 * phase_arr) * 0.12
    wave += np.sin(3 * phase_arr) * 0.06
    wave += np.sin(4 * phase_arr) * 0.03

    # 简单包络（attack 5ms + sustain）
    attack_samples = int(SAMPLE_RATE * 0.005)
    if env_level < 0.99:
        attack_curve = np.minimum(np.arange(frames) / max(attack_samples, 1), 1.0)
        env_curve = env_level + (1.0 - env_level) * attack_curve
    else:
        env_curve = np.ones(frames)
    env_level = env_curve[-1]

    wave = wave * env_curve * 0.45
    outdata[:, 0] = wave.astype(np.float32)

    # 更新显示缓冲
    audio_buffer[:-frames] = audio_buffer[frames:]
    audio_buffer[-frames:] = wave

# ============================================================================
# 自动搜索串口
# ============================================================================
def find_serial_port():
    """尝试自动搜索可用的串口"""
    from serial.tools import list_ports
    ports = list(list_ports.comports())
    if not ports:
        return None
    print("[INFO] 可用串口列表:")
    for p in ports:
        print(f"  {p.device} - {p.description}")
    # 优先选择 FTDI / Digilent / USB Serial
    for p in ports:
        desc = (p.description or '').lower()
        if any(kw in desc for kw in ['ftdi', 'digilent', 'uart', 'serial']):
            return p.device
    # 否则返回第一个
    return ports[0].device

# ============================================================================
# 主函数
# ============================================================================
def main():
    global current_note, _stream, _running

    # 解析串口参数
    if len(sys.argv) > 1:
        port = sys.argv[1]
    else:
        port = find_serial_port()
        if port is None:
            print("[ERROR] 未找到可用串口，请手动指定:")
            print("  python pc_piano.py COM5")
            print("")
            print("提示: 打开设备管理器 -> 端口(COM 和 LPT) 查看 COM 号")
            sys.exit(1)

    print("=" * 60)
    print("  RVP Piano - 实时波形与音频播放")
    print("=" * 60)
    print(f"  串口: {port}")
    print(f"  采样率: {SAMPLE_RATE} Hz")
    print(f"  音符数: 16 (C4 ~ D6)")
    print("-" * 60)
    print("  *** 运行前请确保 MobaXterm 串口会话已关闭! ***")
    print("-" * 60)
    print("  拨动 Nexys4 DDR 上的开关演奏")
    print("  关闭波形窗口退出程序")
    print("-" * 60)

    # 启动 UART 接收线程
    t_uart = threading.Thread(target=uart_receiver, args=(port,), daemon=True)
    t_uart.start()

    # 启动音频输出流
    try:
        _stream = sd.OutputStream(
            callback=audio_callback,
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype='float32',
            blocksize=BUFFER_SAMPLES
        )
        _stream.start()
        print("[AUDIO] 音频流已启动")
    except Exception as e:
        print(f"[AUDIO] 无法启动音频流: {e}")
        print("        请检查音频设备是否正常")
        sys.exit(1)

    # ---- matplotlib 可视化 ----
    plt.style.use('dark_background')
    fig, (ax_wave, ax_piano) = plt.subplots(
        2, 1, figsize=(14, 6),
        gridspec_kw={'height_ratios': [3, 1]}
    )
    fig.suptitle('RVP Piano - 实时波形与琴键显示', fontsize=14, color='white')
    fig.patch.set_facecolor('#1a1a2e')

    # 波形子图
    ax_wave.set_facecolor('#16213e')
    line_wave, = ax_wave.plot(
        np.zeros(DISPLAY_SAMPLES), color='#00d4ff',
        linewidth=0.8, alpha=0.9
    )
    ax_wave.set_ylim(-0.6, 0.6)
    ax_wave.set_xlim(0, DISPLAY_SAMPLES)
    ax_wave.set_title('Waveform (波形)', color='#e0e0e0', fontsize=11)
    ax_wave.set_xlabel('Sample', color='#888', fontsize=9)
    ax_wave.tick_params(colors='#888')
    ax_wave.grid(True, alpha=0.15, color='white')

    # 钢琴键盘子图
    ax_piano.set_facecolor('#1a1a2e')
    key_rects = []
    for i in range(16):
        rect = Rectangle(
            (i, 0), 0.92, 1,
            facecolor='#f0f0f0', edgecolor='#333', linewidth=1.5
        )
        ax_piano.add_patch(rect)
        key_rects.append(rect)
        # 音符名
        color = '#00d4ff' if i % 7 in (0, 3) else '#333'
        ax_piano.text(
            i + 0.46, 0.3, NOTES[i][0],
            ha='center', va='center', fontsize=7, color=color
        )
        # 频率
        ax_piano.text(
            i + 0.46, 0.7, str(NOTES[i][1]),
            ha='center', va='center', fontsize=5.5, color='#999'
        )
    ax_piano.set_xlim(-0.3, 16.3)
    ax_piano.set_ylim(-0.2, 1.3)
    ax_piano.set_title('Piano Keyboard (琴键)', color='#e0e0e0', fontsize=11)
    ax_piano.set_xticks([])
    ax_piano.set_yticks([])

    # 底部状态栏
    status_text = fig.text(
        0.5, 0.01, '', ha='center', fontsize=10,
        color='#00d4ff', family='monospace'
    )

    # ---- 窗口关闭事件处理 ----
    def on_close(event):
        global _running
        print("\n[EXIT] 正在关闭...")
        _running = False
        try:
            if _stream:
                _stream.stop()
                _stream.close()
        except:
            pass
        try:
            if _ser:
                _ser.close()
        except:
            pass
        plt.close('all')

    fig.canvas.mpl_connect('close_event', on_close)

    # ---- 动画更新 ----
    def update(frame):
        with lock:
            note = current_note

        # 更新波形
        line_wave.set_ydata(audio_buffer.copy())

        # 更新琴键颜色
        for i in range(16):
            if note == i + 1:
                key_rects[i].set_facecolor('#e94560')
                key_rects[i].set_edgecolor('#e94560')
            else:
                key_rects[i].set_facecolor('#f0f0f0')
                key_rects[i].set_edgecolor('#333')

        # 状态文本 — 包含 UART 连接状态
        if uart_status == "connected":
            if note > 0:
                name, freq = NOTES[note - 1]
                status_text.set_text(
                    f'  NOTE: {name}  |  FREQ: {freq} Hz  |  UART: OK  |  RX: {uart_bytes_received} bytes  '
                )
                status_text.set_color('#00d4ff')
            else:
                status_text.set_text(
                    f'  SILENCE - 拨动开关演奏  |  UART: OK  |  RX: {uart_bytes_received} bytes  '
                )
                status_text.set_color('#00d4ff')
        elif uart_status == "connecting":
            status_text.set_text('  UART: 连接中...  ')
            status_text.set_color('#ffaa00')
        elif uart_status == "error":
            status_text.set_text(
                f'  UART ERROR: {uart_error_msg}  '
            )
            status_text.set_color('#ff4444')
        else:
            status_text.set_text(
                f'  UART DISCONNECTED: {uart_error_msg}  '
            )
            status_text.set_color('#ff4444')

        return [line_wave] + key_rects + [status_text]

    ani = animation.FuncAnimation(
        fig, update, interval=50, blit=False, cache_frame_data=False
    )
    plt.tight_layout()
    plt.subplots_adjust(bottom=0.08)

    # ---- 阻塞显示，窗口关闭后退出 ----
    plt.show()

    # 确保清理完成
    _running = False
    try:
        if _stream:
            _stream.stop()
            _stream.close()
    except:
        pass
    try:
        if _ser:
            _ser.close()
    except:
        pass

    print("[EXIT] 程序已退出")
    sys.exit(0)

if __name__ == '__main__':
    main()
