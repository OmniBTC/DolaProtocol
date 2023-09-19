from __future__ import annotations

import time
import logging
from eth_abi import decode
from brownie.network.account import LocalAccount
from dola_sui_sdk import sui_project
from dola_ethereum_sdk.load import bool_messenger_package

from .db import BOOLRecordConsumer


class BoolExecutorSui:
    def __init__(
            self,
            cid,
            dst_network,
            dispatch,
            mongodb_uri,
            executor,
            interval=5,
    ):
        self.cid = cid
        self.dst_network = dst_network
        self.interval = interval

        logging.info(
            f"[BoolExecutorSui] init: cid={cid}, dst_network={dst_network}, executor={executor}, interval={interval}"
        )

        self.db_consumer = BOOLRecordConsumer(mongodb_uri)

        if not callable(dispatch):
            raise TypeError("dispatch must be callable")

        self.dispatch = dispatch

        self.executor = executor
        sui_project.active_account(self.executor)

    def run(self):
        while True:
            logging.debug(f"[BoolExecutorSui] waiting {self.interval} seconds...")
            time.sleep(self.interval)

            try:
                records = list(
                    self.db_consumer.find({'status': 'waitForDeliver', 'cid': self.cid}).sort("blockNum", 1).limit(1)
                )

                for record in records:
                    try:
                        # lendingBool.dispatch
                        result = self.dispatch(record["msg"], record["signature"])

                        if result["effects"]["status"]["status"] == "success":
                            status = "Delivered"
                            dstTx = result['effects']['transactionDigest']
                        else:
                            status = "Failed"
                            dstTx = ""
                    except Exception as e:
                        logging.warning(f"[BoolExecutorSui] Deliver record failed: {record['crossId']}, err={e}")
                        status = "Failed"
                        dstTx = ""

                    self.db_consumer.update_record(
                        {'status': 'waitForDeliver', 'crossId': record["crossId"]},
                        {'$set': {'dstTx': dstTx, 'status': status, 'end_time': self.db_consumer.date()}}
                    )

                    logging.info(f"[BoolExecutorSui] Update record: crossId={record['crossId']}, status={status}")
            except Exception as e:
                logging.warning(f"[BoolExecutorSui] Find records failed: {e}")
                continue



class BoolExecutorETH:
    MessageABI = ["bytes32", "bytes32", "bytes32", "bytes", "bytes32", "bytes"]

    def __init__(
            self,
            cid,
            dst_network,
            messenger,
            mongodb_uri,
            executor,
            interval=5
    ):
        self.cid = cid
        self.dst_network = dst_network
        self.interval = interval

        logging.info(
            f"[BoolExecutorETH] init: cid={cid}, dst_network={dst_network}, executor={executor}, interval={interval}"
        )

        if not isinstance(executor, LocalAccount):
            raise TypeError("executor must be brownie.network.account.LocalAccount")

        self.executor = executor
        self.db_consumer = BOOLRecordConsumer(mongodb_uri)
        self.messenger = bool_messenger_package(messenger)

    def run(self):
        while True:
            logging.debug(f"[BoolExecutorETH] waiting {self.interval} seconds...")
            time.sleep(self.interval)

            try:
                records = list(
                    self.db_consumer.find({'status': 'waitForDeliver', 'cid': self.cid}).sort("blockNum", 1).limit(1)
                )

                for record in records:
                    # function receiveFromBool(
                    #     Message memory message,
                    #     bytes calldata signature
                    # ) external override nonReentrant
                    try:
                        msg = bytes.fromhex(record["msg"].replace("0x", ""))
                        signature = bytes.fromhex(record["signature"].replace("0x", ""))

                        receipt = self.messenger.receiveFromBool(
                            decode(self.MessageABI, msg),
                            signature,
                            {"from": self.executor, "gas_price": self.gas_price}
                        )
                        status = "Delivered"
                        dstTx = receipt.txid

                    except Exception as e:
                        logging.warning(f"[BoolExecutorETH] Deliver record failed: {record['crossId']}, err={e}")
                        status = "Failed"
                        dstTx = ""

                    self.db_consumer.update_record(
                        {'status': 'waitForDeliver', 'crossId': record["crossId"]},
                        {'$set': {'dstTx': dstTx, 'status': status, 'end_time': self.db_consumer.date()}}
                    )

                    logging.info(f"[BoolExecutorETH] Update record: crossId={record['crossId']}, status={status}")
            except Exception as e:
                logging.warning(f"[BoolExecutorETH] Find records failed: {e}")
                continue


