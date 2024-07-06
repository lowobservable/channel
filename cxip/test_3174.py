#!/usr/bin/env python

from enum import IntFlag
import struct
import socket
import time

ENCODING = 'ibm037'

def main():
    addr = 0x60 # mock_cu = 0xff

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.connect(('ebaz', 3174))

        cxip_ping(sock)

        print('NOP...')

        (status, _) = cxip_exec(sock, addr, 0x03) # NOP

        print(f'\tstatus = {status!r}')

        print('SENSE ID...')

        (status, data) = cxip_exec(sock, addr, 0xe4, 7) # SENSE ID

        print(f'\tstatus = {status!r}')
        print('\tdata = ' + ' '.join(['{0:02x}'.format(x) for x in data]))

        if data != b'\xff\x31\x74\x1d':
            print('Expected ID to be 31 74 1D for a 3174-1L...')
            return

        aid = None

        while True:
            screen = format_screen(aid)

            print('ERASE/WRITE...')

            (status, _) = cxip_exec(sock, addr, 0x05, screen) # ERASE/WRITE

            print(f'\tstatus = {status!r}')

            wait_for_attn(sock)

            print('ATTN...')

            (status, data) = cxip_exec(sock, addr, 0x06, 64) # READ MODIFIED

            print(f'\tstatus = {status!r}')
            print('\tdata = ' + ' '.join(['{0:02x}'.format(x) for x in data]))

            aid = data[0]

            print(f'\taid = {aid:02x}')

def format_screen(aid):
    screen = bytearray()

    screen.append(0x43) # WCC

    screen += bytes([0x11, 0x40, 0x40]) # SBA
    screen += bytes([0x1d, 0xf8]) # SF
    screen += '3174-1L CXIP TEST PROGRAM'.encode(ENCODING)

    screen += bytes([0x11, 0xc2, 0x60]) # SBA
    screen += bytes([0x1d, 0xf4]) # SF
    screen += 'Press AID key...'.encode(ENCODING)

    if aid is not None:
        screen += bytes([0x11, 0xc5, 0x40]) # SBA
        screen += bytes([0x1d, 0xf4]) # SF
        screen += f'Last AID = {aid:02x}'.encode(ENCODING)

    return screen

class Status(IntFlag):
    ATTN = 0x80
    SM = 0x40
    CUE = 0x20
    BUSY = 0x10
    CE = 0x08
    DE = 0x04
    UC = 0x02
    UX = 0x01

def cxip_ping(sock):
    send_msg(sock, b'\x01')

    while True:
        msg = recv_msg(sock)

        # We can ignore status messages... actually, we probably shouldn't
        # but this is just a hack anyway!
        if msg[0] == 5:
            continue

        if msg != b'\x02':
            raise Exception('Expected PONG')

        return

def cxip_exec(sock, addr, cmd, data_or_count=None):
    flags = 0

    is_write_command = bool(cmd & 0x01)

    data = b''
    count = 0

    if is_write_command:
        if data_or_count:
            data = bytes(data_or_count)
            count = len(data)
    else:
        count = int(data_or_count)

    msg = struct.pack('!BBBBH', 0x03, addr, cmd, flags, count) + data

    send_msg(sock, msg)

    while True:
        msg = recv_msg(sock)

        # We can ignore status messages as they are generated async and
        # will be outdated by the time we receive the EXEC response.
        if msg[0] == 5:
            continue

        if msg[0] != 4:
            raise Exception('Expected EXEC response')

        (result, status, count) = struct.unpack('!BBH', msg[1:5])
        data = msg[5:]

        status = Status(status)

        if result != 0:
            raise Exception(f'EXEC error: {result}')

        if is_write_command:
            return (status, count)
        else:
            return (status, data)

def wait_for_attn(sock):
    while True:
        msg = recv_msg(sock)

        if msg[0] != 5:
            print(f'encountered {msg[0]} message while waiting for status')
            continue

        (addr, status) = struct.unpack('BB', msg[1:])

        status = Status(status)

        print(f'got status {status!r}')

        if status & Status.ATTN:
            return status

def send_msg(sock, msg):
    sock.sendall(struct.pack('!H', len(msg)) + msg)

MSG_BUF = bytearray()

def pop_msg():
    if len(MSG_BUF) < 2:
        return None

    (msg_len,) = struct.unpack('!H', MSG_BUF[:2])

    if len(MSG_BUF) < msg_len + 2:
        return None

    msg = bytes(MSG_BUF[2:msg_len+2])

    del MSG_BUF[:msg_len+2]

    return msg

def recv_msg(sock):
    while True:
        msg = pop_msg()

        if msg is not None:
            return msg

        MSG_BUF.extend(sock.recv(1024))

if __name__ == '__main__':
    main()
