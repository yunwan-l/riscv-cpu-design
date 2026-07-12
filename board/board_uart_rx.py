#!/usr/bin/env python3
"""
board_uart_rx.py — 板载 I-Cache 测试 UART 接收器
=================================================
通过串口接收 FPGA 发送的 I-Cache 测试结果。

协议格式（每个测试发送 11 字节）：
  [标记字节] [hit_delta 4字节大端] [miss_delta 4字节大端] [0x0A换行]
  
标记字节含义：
  'L' (0x4C) = 紧凑循环测试
  'S' (0x53) = 顺序执行测试
  'B' (0x42) = 分支密集测试
  'M' (0x4D) = 混合模式测试

使用方法：
  python board_uart_rx.py [COM端口]
  
  不带参数会自动搜索可用串口。
  常见端口：COM3, COM4, COM5 等（设备管理器查看）

依赖安装：
  pip install pyserial
"""

import sys
import struct
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print('错误: 需要安装 pyserial')
    print('  运行: pip install pyserial')
    sys.exit(1)

# ============================================================================
# 配置
# ============================================================================

BAUD_RATE   = 115200
TIMEOUT_SEC = 10  # 单次接收超时（秒）

MARKER_NAMES = {
    0x4C: '紧凑循环 (Loop)',
    0x53: '顺序执行 (Sequential)',
    0x42: '分支密集 (Branchy)',
    0x4D: '混合模式 (Mixed)',
}

# ============================================================================
# 串口查找
# ============================================================================

def find_serial_port():
    """自动查找可用的串口"""
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print('未找到任何串口设备！')
        print('请确认:')
        print('  1. Nexys4 板已通过 USB 连接到电脑')
        print('  2. 板子已上电（电源开关打开）')
        print('  3. 驱动已安装（Digilent USB-JTAG）')
        return None
    
    # 优先查找 Digilent / FTDI 设备
    for port in ports:
        desc = (port.description or '').lower()
        if 'digilent' in desc or 'ftdi' in desc or 'jtag' in desc:
            return port.device
    
    # 否则返回第一个
    print('可用串口:')
    for p in ports:
        print(f'  {p.device}: {p.description}')
    return ports[0].device

# ============================================================================
# 接收解析
# ============================================================================

def receive_result(ser):
    """
    接收一个完整的测试结果（11字节）
    返回: (marker, hit_delta, miss_delta) 或 None
    """
    # 1. 等待标记字节
    marker = None
    raw = b''
    
    while True:
        byte = ser.read(1)
        if not byte:
            return None  # 超时
        
        b = byte[0]
        raw += byte
        
        if b in MARKER_NAMES:
            marker = b
            break
        # 忽略非标记字节（可能是上次残留的换行等）
    
    # 2. 接收 8 字节数据 (hit_delta + miss_delta)
    data = ser.read(8)
    if len(data) < 8:
        print(f'  错误: 只收到 {len(data)} 字节数据（期望8字节）')
        return None
    
    hit_delta  = struct.unpack('>I', data[0:4])[0]
    miss_delta = struct.unpack('>I', data[4:8])[0]
    
    # 3. 接收换行符
    nl = ser.read(1)
    
    return (marker, hit_delta, miss_delta)

# ============================================================================
# 主循环
# ============================================================================

def main():
    # 确定串口
    if len(sys.argv) > 1:
        port_name = sys.argv[1]
    else:
        port_name = find_serial_port()
        if port_name is None:
            print('\n请手动指定串口: python board_uart_rx.py COM3')
            return
    
    print(f'PMRU8 I-Cache 板载测试接收器')
    print(f'=' * 50)
    print(f'串口: {port_name}')
    print(f'波特率: {BAUD_RATE}')
    print(f'等待数据... (按 Ctrl+C 退出)')
    print(f'')
    print(f'协议: [标记1B] [hit_delta 4B大端] [miss_delta 4B大端] [\\n]')
    print(f'')
    print(f'{"时间":<12} {"测试类型":<25} {"命中":>8} {"未命中":>8} {"命中率":>8}')
    print(f'{"-"*12} {"-"*25} {"-"*8} {"-"*8} {"-"*8}')
    
    try:
        with serial.Serial(port_name, BAUD_RATE, timeout=TIMEOUT_SEC) as ser:
            count = 0
            while True:
                result = receive_result(ser)
                if result is None:
                    print('  (超时，未收到数据)')
                    print('  请确认:')
                    print('    1. FPGA 已烧录并运行')
                    print('    2. 程序已执行到报告代码')
                    print('    3. UART 连接正确 (D4引脚)')
                    continue
                
                marker, hit_delta, miss_delta = result
                test_name = MARKER_NAMES.get(marker, f'未知(0x{marker:02X})')
                total = hit_delta + miss_delta
                if total > 0:
                    hit_rate = hit_delta * 100.0 / total
                else:
                    hit_rate = 0.0
                
                timestamp = time.strftime('%H:%M:%S')
                print(f'{timestamp:<12} {test_name:<25} {hit_delta:>8} {miss_delta:>8} {hit_rate:>7.1f}%')
                count += 1
                
    except KeyboardInterrupt:
        print(f'\n\n已停止。共接收 {count} 条结果。')
    except serial.SerialException as e:
        print(f'\n串口错误: {e}')
        print('请确认串口未被其他程序占用')

if __name__ == '__main__':
    main()
