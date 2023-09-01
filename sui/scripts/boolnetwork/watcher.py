from __future__ import annotations

import logging
import time

from substrateinterface import SubstrateInterface
from .message import TxMessage, EventSubmitTransaction
from .db import BOOLRecordProducer
from .verify import ECDSAPublicKey, ED25519PublicKey
from .type import BoolTypes


def subscription_handler(obj, update_nr, subscription_id):
    block = obj["header"]["number"]

    logging.debug(
        f"[BoolWatcher] subscription_handler: New block #{block}, #{update_nr}, @{subscription_id}"
    )

    if update_nr > 10:
        return {
            "message": "Subscription will cancel when a value is returned",
            "updates_processed": update_nr,
        }

    return block


class BoolWatcher:
    def __init__(
            self,
            ws_url,
            mongodb_uri,
            config: dict = None,
            begin_num: int = None,
            max_block_range: int = 100,
            wait_seconds: int = 10,
            verify: bool = False,
    ):
        self.url = ws_url
        self.provider = SubstrateInterface(
            url=ws_url, type_registry=BoolTypes, type_registry_preset="legacy"
        )
        self.max_block_range = max_block_range

        self.latest = self._latest_number()
        self.wait_seconds = wait_seconds
        self.verify = verify
        self.db = BOOLRecordProducer(mongodb_uri=mongodb_uri)

        if begin_num is None or begin_num <= 10:
            begin_num = self.latest

        self.begin_num = begin_num

        self.filter_cids = []
        self.sui_cids = []
        self.public_keys = {}
        for cid, key_info in config.items():
            self.filter_cids.append(cid)
            if key_info["key_type"] == "eddsa":
                self.sui_cids.append(cid)
                self.public_keys[cid] = ED25519PublicKey(key_info["committee_key"])
            else:
                self.public_keys[cid] = ECDSAPublicKey(key_info["committee_key"])

        logging.info(
            f"[BoolWatcher] init: begin_num={self.begin_num}, "
            f"latest_num={self.latest}, "
            f"max_block_range={self.max_block_range}, "
            f"filter_cids={self.filter_cids}, "
            f"sui_cids={self.sui_cids}"
        )

    def _latest_number(self):
        latest_hash = self.provider.get_chain_finalised_head()
        return self.provider.get_block_number(latest_hash)

    def _filter_events(
            self,
            pallet_name="Channel",
            event_name="SubmitTransaction",
            block_start: int = None,
            block_end: int = None,
    ):
        if block_end is None:
            block_end = self.provider.get_block_number("")

        if block_start is None:
            block_start = block_end

        if block_start < 0:
            block_start += block_end

        # Requirements check
        if block_end - block_start > self.max_block_range:
            logging.error(
                f"[BoolWatcher] max_block_range: ({self.max_block_range}) exceeded"
            )
            raise ValueError("BoolWatcher _filter_events")

        result = []

        logging.info(
            f"[BoolWatcher] _filter_events: begin [#{block_start}, #{block_end}]"
        )

        for block_number in range(block_start, block_end + 1):
            block_hash = self.provider.get_block_hash(block_number)
            for event in self.provider.get_events(block_hash=block_hash):

                if (
                        pallet_name is not None
                        and pallet_name != event.value["event"]["module_id"]
                ):
                    continue

                if (
                        event_name is not None
                        and event_name != event.value["event"]["event_id"]
                ):
                    continue

                e = EventSubmitTransaction(block_number, block_hash, event.value)

                logging.debug(f"[BoolWatcher] _filter_events: event={e}")

                if e.cid not in self.filter_cids:
                    continue

                result.append(e)

        logging.info(f"[BoolWatcher] _filter_events: end [#{block_start}, #{block_end}]")

        return result

    def _verify_msg(self, cid: int, msg: bytes, signature: bytes):
        return self.public_keys[cid].verify(msg, signature)

    def _query_storage(self, event):
        tx_msg = TxMessage(event)

        storage_obj = self.provider.query(
            module="Channel",
            storage_function="TxMessages",
            block_hash=tx_msg.event.block_hash,
            params=[tx_msg.event.cid, tx_msg.event.verify_hash],
        )

        to_sui = True if tx_msg.event.cid in self.sui_cids else False

        tx_msg.parse_storage_obj(storage_obj, to_sui)

        if self.verify:
            try:
                assert self._verify_msg(tx_msg.event.cid, tx_msg.msg, tx_msg.signature)
            except Exception as e:
                logging.error(f"[BoolWatcher] _verify_msg: tx_msg={tx_msg}")
                raise e

        self.db.add_wait_record(tx_msg.format_json())

        logging.info(f"[BoolWatcher] _query_storage: tx_msg={tx_msg}")

    def _query_events(self):
        # TODO: parallel processing
        while self.begin_num < self.latest:
            batch = min(self.latest - self.begin_num, self.max_block_range)
            events = self._filter_events(
                block_start=self.begin_num, block_end=self.begin_num + batch
            )
            for event in events:
                self._query_storage(event)

            self.begin_num = self.begin_num + batch + 1
            self.latest = self._latest_number()

    def run(self):

        self._query_events()

        while True:
            self.latest = self.provider.subscribe_block_headers(
                subscription_handler, finalized_only=True
            )

            logging.info(
                f"[BoolWatcher] subscribe: begin [#{self.begin_num}, #{self.latest}]"
            )

            if self.latest <= self.begin_num:
                logging.info(
                    f"[BoolWatcher] subscribe: waiting {self.wait_seconds} seconds for next latest block"
                )
                time.sleep(self.wait_seconds)
                continue

            try:
                events = self._filter_events(
                    block_start=self.begin_num,
                    block_end=self.latest
                )
            except ValueError:
                self._query_events()
                continue
            except Exception as e:
                logging.warning(e)
                continue

            for event in events:
                self._query_storage(event)

            logging.info(
                f"[BoolWatcher] subscribe: end [#{self.begin_num}, #{self.latest}]"
            )

            self.begin_num = self.latest + 1

            # waiting some seconds
            time.sleep(self.wait_seconds)
