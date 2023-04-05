# @Time    : 2023/3/29 13:07
# @Author  : WeiDai
# @FileName: test_sui_brownie.py
import unittest
from pathlib import Path

from sui_brownie import Argument, U16
from sui_brownie.sui_brownie import SuiProject, SuiPackage, TransactionBuild


class TestSuiBrownie(unittest.TestCase):

    @staticmethod
    def load_project():
        return SuiProject(project_path=Path.cwd().joinpath("TestProject"), network="sui-testnet")

    def test_project(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

    def test_publish_package(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        sui_project.unsafe_pay_all_sui()

        math = SuiPackage(package_path=Path.cwd().joinpath("TestProject/math"))
        math.publish_package(replace_address=dict(math="0x0"))
        math.program_publish_package(replace_address=dict(math="0x0"))

        # basics = SuiPackage(package_path=Path.cwd().joinpath("TestProject/basics"))
        # basics.publish_package(replace_address=dict(Math=math.package_id))

        basics = SuiPackage(package_path=Path.cwd().joinpath("TestProject/basics"))
        basics.publish_package(replace_address=dict(Math=None))
        basics.program_publish_package(replace_address=dict(Math=None))

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

        dola_portal = SuiPackage(package_id="0x420d506a6bc1b6b2530ebcbda785f684de0ea7ff8c66644a334bf3fd662b050b",
                                 package_name="DolaPortal"
                                 )
        print(dola_portal.lending.supply)

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
        basics.counter.create.unsafe()
        basics.counter.increment.unsafe(basics.counter.Counter[-1])

    def test_pay(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")
        sui_project.pay_all_sui()

        sui_project.pay_sui(amounts=[0])

    def test_package_call(self):
        sui_project = self.load_project()
        sui_project.active_account("Relayer")

        basics = SuiPackage(package_id=sui_project.Basics[-1],
                            package_name="Basics"
                            )
        basics.counter.create()
        sui_project.batch_transaction(
            actual_params=[basics.counter.Counter[-1], 2],
            transactions=[
                [basics.counter.increment, [Argument("Input", U16(0))], []],
                [basics.counter.assert_value, [Argument("Input", U16(0)), Argument("Input", U16(1))], []],
            ]
        )
        basics.counter.test_param(basics.counter.Counter[-1],
                                  [10089869, 234567],
                                  1,
                                  8,
                                  [9],
                                  [[9, 9]],
                                  [[9, 8]],
                                  type_arguments=["U64"]
                                  )

        basics.counter.test_vec_object(
            ["0x543a78751e8f24bfabc089020c4bdd425c25ef38648a0131b9906fe19c9b1fdb"],
            type_arguments=["0xe6ea734a94c6edb3c6f964a5ab880f1773fd5f58fb1b7fb4be4e521ce94078d7::counter::USDT"]
        )

        basics.counter.test_vec_object.with_gas_coin(
            ["0x009e62a155ad5f89ef78b01ca2772b429e141438ab70661730f4be154c3efb63"],
            1,
            type_arguments=["0x2::sui::SUI"]
        )
