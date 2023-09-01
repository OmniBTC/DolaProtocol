from __future__ import annotations

import time
import logging
from eth_abi import decode
from dola_sui_sdk.load import booltest_anchor_package
from dola_sui_sdk import sui_project
from dola_ethereum_sdk.load import booltest_messenger_package

from .db import BOOLRecordConsumer


class BoolExecutorSui:
    def __init__(
            self,
            cid,
            dst_network,
            dst_contract,
            mongodb_uri,
            interval=5,
            other: dict = None
    ):
        self.cid = cid
        self.dst_network = dst_network
        self.dst_contract = dst_contract
        self.interval = interval

        logging.info(f"[BoolExecutorSui] init: cid={cid}, dst_network={dst_network}, "
                     f"dst_contract={dst_contract}, interval={interval}, other={other}")

        self.executor = other["executor"]
        self.anchor_cap = other["anchor_cap"]
        self.global_state = other["global_state"]

        self.db_consumer = BOOLRecordConsumer(mongodb_uri)
        self.anchor = booltest_anchor_package(dst_contract)
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
                    # public entry fun receive_message(
                    #     message_raw: vector<u8>,
                    #     signature: vector<u8>,
                    #     anchor_cap: &AnchorCap,
                    #     state: &mut GlobalState,
                    #     _ctx: &mut TxContext,
                    # )

                    try:
                        msg = bytes.fromhex(record["msg"].replace("0x", ""))
                        signature = bytes.fromhex(record["signature"].replace("0x", ""))

                        result = self.anchor.consumer_receivable.receive_message(
                            list(msg),
                            list(signature),
                            self.anchor_cap,
                            self.global_state
                        )

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
            dst_contract,
            mongodb_uri,
            interval=5,
            other: dict = None
    ):
        self.cid = cid
        self.dst_network = dst_network
        self.dst_contract = dst_contract
        self.interval = interval

        logging.info(f"[BoolExecutorETH] init: cid={cid}, dst_network={dst_network}, "
                     f"dst_contract={dst_contract}, interval={interval}, other={other}")

        self.executor = other["executor"]

        self.gas_price = 100000000 if "bevm" in dst_contract else None

        self.db_consumer = BOOLRecordConsumer(mongodb_uri)
        self.messenger = booltest_messenger_package(dst_contract)

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


