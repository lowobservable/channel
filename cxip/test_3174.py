#!/usr/bin/env python

from enum import IntFlag
import struct
import socket
import time

ENCODING = 'ibm037'

CMD_NOP = 0x03
CMD_SENSE_ID = 0xe4
CMD_EW = 0x05 # Erase / Write
CMD_RM = 0x06 # Read Modified

def main():
    addr = 0x60

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.connect(('ebaz1', 3174))

        cxip_ping(sock)

        cxip_open(sock, addr)

        print('NOP...')

        (status, _) = cxip_exec(sock, addr, CMD_NOP)

        print(f'\tstatus = {status!r}')

        print('SENSE ID...')

        (status, data) = cxip_exec(sock, addr, CMD_SENSE_ID, 7)

        print(f'\tstatus = {status!r}')
        print('\tdata = ' + ' '.join(['{0:02x}'.format(x) for x in data]))

        if data != b'\xff\x31\x74\x1d':
            print('Expected ID to be 31 74 1D for a 3174-1L...')
            return

        aid = None

        while True:
            screen = format_screen(aid)

            print('ERASE/WRITE...')

            (status, _) = cxip_exec(sock, addr, CMD_EW, screen)

            print(f'\tstatus = {status!r}')

            (_, status, solicited) = wait_for_status(sock)

            if not solicited and Status.ATTN in status:
                print('ATTN!')
                print('READ MODIFIED...')

                (status, data) = cxip_exec(sock, addr, CMD_RM, 64)

                print(f'\tstatus = {status!r}')
                print('\tdata = ' + ' '.join(['{0:02x}'.format(x) for x in data]))

                aid = data[0]

                print(f'\taid = {aid:02x}')
            else:
                print(f'Unexpected status: {status!r}')

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
    send_msg(sock, struct.pack('B', 0x01))

    while True:
        msg = recv_msg(sock)

        if msg[0] != 0x00:
            raise Exception('Expected ACK response')

        return

def cxip_open(sock, addr):
    send_msg(sock, struct.pack('BB', 0x02, addr))

    while True:
        msg = recv_msg(sock)

        if msg[0] != 0x00:
            raise Exception('Expected ACK response')

        return

def cxip_exec(sock, addr, cmd, data_or_count=None):
    flags = 0

    is_send_cmd = bool(cmd & 0x01)

    data = b''
    count = 0

    if is_send_cmd:
        if data_or_count:
            data = bytes(data_or_count)
            count = len(data)

        msg = struct.pack('!BBBB', 0x04, addr, cmd, flags) + data
    else:
        count = int(data_or_count)

        msg = struct.pack('!BBBBH', 0x04, addr, cmd, flags, count)

    send_msg(sock, msg)

    cumulative_status = 0
    done = False

    while not done:
        msg = recv_msg(sock)

        if msg[0] == 0x06 and is_send_cmd:
            (count,) = struct.unpack('!H', msg[2:])
        elif msg[0] == 0x06 and not is_send_cmd:
            data = msg[2:]
            count = len(data)
        elif msg[0] == 0x05:
            (_, status, status_flags) = struct.unpack('BBB', msg[1:])

            status = Status(status)
            solicited = bool(status_flags)

            if not solicited:
                raise Exception('Expected status to be solicited')

            cumulative_status |= status

            # NOTE: See libchan chan_exec for assumption.
            done = (status != Status.CE)
        else:
            raise Exception('Expected STATUS or DATA response')

    if is_send_cmd:
        return (status, count)
    else:
        return (status, data)

def wait_for_status(sock):
    msg = recv_msg(sock)

    if msg[0] != 0x05:
        raise Exception('Expected STATUS response')

    (addr, status, flags) = struct.unpack('BBB', msg[1:])

    status = Status(status)
    solicited = bool(flags)

    return (addr, status, solicited)

def send_msg(sock, msg):
    sock.sendall(struct.pack('!BH', 0, len(msg)) + msg)

MSG_BUF = bytearray()

def pop_msg():
    if len(MSG_BUF) < 3:
        return None

    (msg_version, msg_len) = struct.unpack('!BH', MSG_BUF[:3])

    if len(MSG_BUF) < msg_len + 3:
        return None

    msg = bytes(MSG_BUF[3:msg_len+3])

    del MSG_BUF[0:msg_len+3]

    return msg

def recv_msg(sock):
    while True:
        msg = pop_msg()

        if msg is not None:
            if msg[0] == 0xff:
                num = msg[1]
                text = msg[2:].decode('ascii')

                if num == 0:
                    raise Exception(text)

                raise Exception(f'{num}: {text}')

            return msg

        MSG_BUF.extend(sock.recv(1024))

if __name__ == '__main__':
    main()
