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
        self.db = db['BoolRecord']

        self._create_index()

    def _create_index(self):
        self.db.create_index("crossId", unique=True)

    def find_one(self, filter):
        return self.db.find_one(filter)

    def find(self, filter):
        return self.db.find(filter)

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
            self.db.insert_one(record)
        except errors.DuplicateKeyError:
            pass


class BOOLRecordConsumer(BOOLRecord):
    def update_record(self, filter, update):
        self.db.update_one(filter, update)
