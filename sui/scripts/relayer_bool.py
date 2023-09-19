import functools
import logging
from dotenv import dotenv_values
from pathlib import Path

from sui_brownie.parallelism import ProcessExecutor

import dola_ethereum_sdk
from dola_ethereum_sdk import get_account
import dola_sui_sdk
from dola_sui_sdk.load import sui_project
from dola_sui_sdk.lendingBool import dispatch

from boolnetwork import BoolWatcher, BoolExecutorETH, BoolExecutorSui


def get_mongodb_uri():
    env_file = sui_project.config['dotenv']
    env_values = dotenv_values(sui_project.project_path.joinpath(env_file))
    return env_values['MONGODB_URI']


dola_sui_sdk.set_dola_project_path(Path("../.."), network="sui-testnet")

bool_network_config = sui_project.network_config["bool_network"]


def run_watcher(
        wss_url,
        config,
        max_block_range,
        begin_num,
        verify: bool = False
):
    BoolWatcher(
        wss_url,
        get_mongodb_uri(),
        config=config,
        max_block_range=max_block_range,
        begin_num=begin_num,
        verify=verify,
    ).run()


def run_executor_sui(
        cid,
        dst_network,
        dispatch,
):
    # path, network, account

    # dola_sui_sdk.set_dola_project_path(Path("../.."), dst_network)

    BoolExecutorSui(
        cid,
        dst_network,
        dispatch,
        get_mongodb_uri(),
        "TestAccount",
        interval=5
    ).run()


def run_executor_eth(
        cid,
        dst_network,
        messenger
):
    # path, network, account
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_ethereum_network(dst_network)

    executor = get_account()

    BoolExecutorETH(
        cid,
        dst_network,
        messenger,
        get_mongodb_uri(),
        executor,
        interval=5,
    ).run()


class ColorFormatter(logging.Formatter):
    grey = '\x1b[38;21m'
    green = '\x1b[92m'
    yellow = '\x1b[38;5;226m'
    red = '\x1b[38;5;196m'
    bold_red = '\x1b[31;1m'
    reset = '\x1b[0m'

    def __init__(self, fmt):
        super().__init__()
        self.fmt = fmt
        self.FORMATS = {
            logging.DEBUG: self.grey + self.fmt + self.reset,
            logging.INFO: self.green + self.fmt + self.reset,
            logging.WARNING: self.yellow + self.fmt + self.reset,
            logging.ERROR: self.red + self.fmt + self.reset,
            logging.CRITICAL: self.bold_red + self.fmt + self.reset
        }

    def format(self, record):
        log_fmt = self.FORMATS.get(record.levelno)
        formatter = logging.Formatter(log_fmt)
        return formatter.format(record)


def init_logger():
    FORMAT = '%(asctime)s - %(funcName)s - %(levelname)s - %(name)s: %(message)s'
    logger = logging.getLogger()
    logger.setLevel("INFO")
    # create console handler with a higher log level
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)

    ch.setFormatter(ColorFormatter(FORMAT))

    logger.addHandler(ch)


def testnet():
    bool_node_url = bool_network_config["node_url"]
    bool_cids = bool_network_config["cids"]
    bool_sui_config = bool_network_config["chains"]["sui-testnet"]
    bool_bevm_config = bool_network_config["chains"]["bevm-testnet"]


    pt = ProcessExecutor(executor=3)

    pt.run([
        functools.partial(
            run_watcher,
            bool_node_url,
            bool_cids,
            20,
            7298606,
            True
        ),
        functools.partial(
            run_executor_sui,
            bool_sui_config["cid"],
            "sui-testnet",
            dispatch
        ),
        functools.partial(
            run_executor_eth,
            bool_bevm_config["cid"],
            "bevm-test",
            bool_bevm_config["messenger"]
        )
    ])


if __name__ == '__main__':
    init_logger()
    testnet()
