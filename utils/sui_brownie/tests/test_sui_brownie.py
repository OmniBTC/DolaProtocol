# @Time    : 2023/3/29 13:07
# @Author  : WeiDai
# @FileName: test_sui_brownie.py
import time
import unittest
from pathlib import Path

from sui_brownie.sui_brownie import SuiProject, SuiPackage, TransactionBuild


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

        # basics = SuiPackage(package_path=Path.cwd().joinpath("TestProject/basics"))
        # basics.publish_package(replace_address=dict(Math=math.package_id))

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

        basics = SuiPackage(package_id=sui_project.Basics[-1],
                            package_name="Basics"
                            )
        print(basics.counter.test_data_type)

    def test_type_arg(self):
        type_arg = "Vector<0xcad9befcc5684c53de572ca6332b873fab338bcd7a244d6614bff57f2ab35444::counter::Data<U8>>"
        result = TransactionBuild.generate_type_arg(type_arg)
        print(result.encode.hex())

        type_arg = "Vector<0xcad9befcc5684c53de572ca6332b873fab338bcd7a244d6614bff57f2ab35444::counter::Data<" \
                   "0xcad9befcc5684c53de572ca6332b873fab338bcd7a244d6614bff57f2ab35444::counter::Data<U8>>>"
        result = TransactionBuild.generate_type_arg(type_arg)
        print(result.encode.hex())

        type_args = ["Vector<0xcad9befcc5684c53de572ca6332b873fab338bcd7a244d6614bff57f2ab35444::counter::Data<U8>",
                     "Vector<Vector<U8>>"
                     ]
        result = TransactionBuild.format_type_args(type_args)
        print(result)

    def test_package_call_unsafe(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        basics = SuiPackage(package_id=sui_project.Basics[-1],
                            package_name="Basics"
                            )
        # basics.counter.create.unsafe()
        basics.counter.increment.unsafe("0x5eea17ae869916058fcc86140745b295db99a3c254f9b4d174354c9e065a3504")

    def test_package_call(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        basics = SuiPackage(package_id=sui_project.Basics[-1],
                            package_name="Basics"
                            )
        # basics.counter.create()
        # basics.counter.increment("0x4486d2743ef05ea1002069d2bd4eaad7ec119aa0cdf61f4bc9d7b64c75fe9e89")
        # basics.counter.set_value("0x4486d2743ef05ea1002069d2bd4eaad7ec119aa0cdf61f4bc9d7b64c75fe9e89", 2)
        # basics.counter.assert_value("0x4486d2743ef05ea1002069d2bd4eaad7ec119aa0cdf61f4bc9d7b64c75fe9e89", 2)
        basics.counter.test_param("0x4486d2743ef05ea1002069d2bd4eaad7ec119aa0cdf61f4bc9d7b64c75fe9e89",
                                  [10089869, 234567],
                                  1,
                                  8,
                                  [9],
                                  [[9, 9]],
                                  [[9, 8]],
                                  type_arguments=["U64"]
                                  )


