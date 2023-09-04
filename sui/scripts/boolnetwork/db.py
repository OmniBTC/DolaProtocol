from __future__ import annotations

from pymongo import MongoClient, errors
import time
import datetime


def mongodb(mongodb_uri):
    mclient = MongoClient(mongodb_uri)
    return mclient["DolaProtocol"]


class BOOLRecord:
    def __init__(self, mongodb_uri):
        db = mongodb(mongodb_uri)
        self.record_collection = db['BoolRecord']
        self.latest_scan = db['BoolLatestScan']

        self._create_index()

    def _create_index(self):
        self.record_collection.create_index("crossId", unique=True)

    def find_one(self, filter):
        return self.record_collection.find_one(filter)

    def find(self, filter):
        return self.record_collection.find(filter)

    def date(self):
        current_timestamp = int(time.time())
        date = str(datetime.datetime.fromtimestamp(current_timestamp))

        return date

class BOOLRecordProducer(BOOLRecord):
    def add_wait_record(self, message: dict):
        record = {
            "txUid": message["txUid"],
            "crossId": message["crossId"],
            "cid": message["cid"],
            "verifyHash": message["verifyHash"],
            "blockNum": message["blockNum"],
            "blockHash": message["blockHash"],
            "msg": message["msg"],
            "signature": message["signature"],
            'status': 'waitForDeliver',
            'dstTx': "",
            'start_time': self.date(),
            'end_time': "",
        }

        try:
            self.record_collection.insert_one(record)
        except errors.DuplicateKeyError:
            pass

    def upsert_latest_scan(self, block_num: int):
        self.latest_scan.update_one(
            {"name": "latest_scan"},
            {'$set': {"name": "latest_scan", "block_num": block_num, "update": self.date()}},
            upsert=True
        )

    def get_latest_scan_num(self):
        latest_scan = self.latest_scan.find_one(
            {"name": "latest_scan"}
        )

        if latest_scan is None:
            return 0
        else:
            return latest_scan["block_num"]


class BOOLRecordConsumer(BOOLRecord):
    def update_record(self, filter, update):
        self.record_collection.update_one(filter, update)
