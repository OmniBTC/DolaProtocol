# @Time    : 2022/11/24 13:50
# @Author  : WeiDai
# @FileName: utils.py


def get_bytes(string: str) -> bytes:
    if isinstance(string, bytes):
        byte = string
    elif isinstance(string, str):
        if string[:2] == "0x":
            string = string[2:]
        byte = bytes.fromhex(string)
    else:
        raise TypeError("Agreement must be either 'bytes' or 'string'!")
    return byte


def padding_to_bytes(data: str, padding="right", length=32) -> str:
    if data[:2] == "0x":
        data = data[2:]
    padding_length = length * 2 - len(data)
    if padding == "right":
        return "0x" + data + "0" * padding_length
    else:
        return "0x" + "0" * padding_length + data


def judge_hex_str(data: str):
    flag = True
    if "0x" == data[:2]:
        data = data[2:]
    for k in data:
        if "0" <= k <= "9" or "a" <= k <= "f" or "A" <= k <= "F":
            continue
        flag = False
    return flag
