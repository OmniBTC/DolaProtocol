# @Time    : 2023/3/29 13:07
# @Author  : WeiDai
# @FileName: test_sui_brownie.py
import time
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

        math = SuiPackage(package_path=Path.cwd().joinpath("TestProject/math"))
        math.publish_package(replace_address=dict(math="0x0"))

        basics = SuiPackage(package_path=Path.cwd().joinpath("TestProject/basics"))
        basics.publish_package(replace_address=dict(Math=math.package_id))

        basics = SuiPackage(package_path=Path.cwd().joinpath("TestProject/basics"))
        basics.publish_package(replace_address=dict(Math=None))

    def test_project_index(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        print(sui_project.Math[-1])
        print(sui_project["Math"][-1])

    def test_package_index(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        math = SuiPackage(package_id="0x1b57e5fd1bf38dd5d3249d66cabf975f64c2ce04e876ba66d1cd48a50a7c8a49",
                          package_name="Math"
                          )
        print(math.sandwich.Grocery)
        print(math.lock.create)
        print(math.lock.key_for)
        print(math.counter.set_value)

    def test_package_call(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        math = SuiPackage(package_id="0x1b57e5fd1bf38dd5d3249d66cabf975f64c2ce04e876ba66d1cd48a50a7c8a49",
                          package_name="Math"
                          )
        math.counter.create()
