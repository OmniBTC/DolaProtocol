# @Time    : 2023/3/29 13:07
# @Author  : WeiDai
# @FileName: test_sui_brownie.py
import unittest
from pathlib import Path

from sui_brownie.sui_brownie_new import SuiProject, SuiPackage


class TestSuiBrownie(unittest.TestCase):

    @staticmethod
    def load_project():
        return SuiProject(project_path=Path.cwd().joinpath("TestProject"), network="sui-devnet")

    def test_project(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

    def test_publish_package(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        basics = SuiPackage(package_path=Path.cwd().joinpath("TestProject/basics"))
        basics.publish_package()
