# @Time    : 2022/11/28 11:07
# @Author  : WeiDai
# @FileName: __init__.py
from pathlib import Path
from typing import Union

DOLA_CONFIG = {
    "DOLA_PROJECT_PATH": Path("../../.."),
    "DOLA_APTOS_PATH": Path("../../..").joinpath("aptos")
}


def set_dola_project_path(path: Union[Path, str]):
    if isinstance(path, str):
        path = Path(path)
    DOLA_CONFIG["DOLA_PROJECT_PATH"] = path
    DOLA_CONFIG["DOLA_APTOS_PATH"] = path.joinpath("aptos")
    assert DOLA_CONFIG["DOLA_APTOS_PATH"].exists(), f"Path error:{DOLA_CONFIG['DOLA_APTOS_PATH'].absolute()}!"

