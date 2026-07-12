#!/usr/bin/env python3
"""
read_uart.py — 读取Nexys4 DDR UART输出的cache测试数据并解码
"""
import serial
import struct
import sys
import time

PORT = 'COM6'
BAUD = 115200

def main():
    print(f"正在打开 {PORT} (波特率 {BAUD})...")
    try:
        ser = serial.Serial(PORT, BAUD, timeout=2)
    except Exception as e:
        print(f"无法打开串口: {e}")
        print("请确认：1) 板子已上电 2) MobaXterm已关闭该串口 3) COM6端口正确")
        sys.exit(1)

    print(f"串口已打开。")
    print(">>> 现在请按板子上的 CPU_RESETN 按钮复位 <<<")
    print("等待数据中... (最多等120秒)\n")

    # 读取数据
    data = bytearray()
    start_time = time.time()
    while time.time() - start_time < 120:  # 最多等120秒
        chunk = ser.read(64)
        if chunk:
            data.extend(chunk)
            print(f"  收到 {len(chunk)} 字节: {chunk.hex()}")
            # 收到数据后继续读一小段时间确保读完
            if len(data) >= 10:
                time.sleep(0.5)
                extra = ser.read(64)
                if extra:
                    data.extend(extra)
                    print(f"  追加 {len(extra)} 字节: {extra.hex()}")
                break
        # 每10秒提示一次
        elapsed = int(time.time() - start_time)
        if elapsed > 0 and elapsed % 10 == 0 and not data:
            print(f"  已等待 {elapsed} 秒，请按 CPU_RESETN 按钮复位...")

    if len(data) < 10:
        print(f"\n只收到 {len(data)} 字节，数据不完整。")
        if data:
            print(f"原始数据(hex): {data.hex()}")
        print("请重新运行此脚本并按复位按钮。")
        ser.close()
        sys.exit(1)

    print(f"\n收到 {len(data)} 字节数据")
    print(f"原始数据(hex): {data.hex()}")
    print()

    # 解码
    marker = data[0]
    hit_delta = struct.unpack('>I', data[1:5])[0]
    miss_delta = struct.unpack('>I', data[5:9])[0]

    marker_map = {0x4C: 'Loop (紧凑循环)', 0x53: 'Sequential (顺序执行)',
                  0x42: 'Branchy (分支密集)', 0x4D: 'Mixed (混合模式)'}
    test_name = marker_map.get(marker, f'未知(0x{marker:02X})')

    total = hit_delta + miss_delta
    hit_rate = hit_delta / total * 100 if total > 0 else 0
    led_val = int(hit_delta * 1000 / total) if total > 0 else 0

    print("=" * 50)
    print(f"  测试类型:   {test_name}")
    print(f"  标记字节:   0x{marker:02X} ('{chr(marker) if 32 <= marker < 127 else '?'}')")
    print(f"  命中次数:   {hit_delta}")
    print(f"  未命中次数: {miss_delta}")
    if total > 0:
        print(f"  总访问数:   {total}")
        print(f"  命中率:     {hit_rate:.4f}%")
        print(f"  LED显示值:  {led_val} (千分比，即{led_val/10:.1f}%)")
    print("=" * 50)

    ser.close()

if __name__ == '__main__':
    main()
