"""
@Time : 2020/10/11 11:52
@Author : DaiWei
@File : _Parallelism.py
"""
from __future__ import annotations
import multiprocessing
import abc
import threading
import ctypes
import inspect
import queue
import asyncio
from typing import List


def _add_flag(func, uid):
    """
    :param func:
    :param uid:
    :return:
    """

    def wrapper(*args, **kwargs):
        return uid, func(*args, **kwargs)

    return wrapper


class _MyThread(threading.Thread):

    def __init__(self, tasks: list = None, callback=None):
        super(_MyThread, self).__init__()
        self.__tasks = tasks
        self.__callback = callback
        self.__die = False

    @property
    def tasks(self):
        return self.__tasks

    @tasks.setter
    def tasks(self, value):
        self.__tasks = value

    @property
    def callback(self):
        return self.__callback

    @callback.setter
    def callback(self, value):
        self.__callback = value

    def is_die(self):
        return self.__die

    def run(self):
        if self.__tasks is None:
            print("tasks is None")
        else:
            for target in self.__tasks:
                result = target()
                if self.__callback is not None:
                    self.__callback(result)
        self.__die = True


def data_block(data: list or tuple, block_num: int) -> List[list]:
    out = [[] for _ in range(block_num)]
    for k, v in enumerate(data):
        out[k % block_num].append(v)
    return out


class _MyThreadPool:
    def __init__(self, max_worker=1):
        if isinstance(max_worker, int):
            self.__workers = [_MyThread() for _ in range(max_worker)]
        else:
            print("max_worker must be int")

    @staticmethod
    def _async_raise(tid, exc_type):

        tid = ctypes.c_long(tid)
        if not inspect.isclass(exc_type):
            exc_type = type(exc_type)
        res = ctypes.pythonapi.PyThreadState_SetAsyncExc(
            tid, ctypes.py_object(exc_type))
        if res == 0:
            raise ValueError("invalid thread id")
        elif res != 1:
            # """if it returns a number greater than one, you're in trouble,
            # and you should call it again with exc=NULL to revert the effect"""
            ctypes.pythonapi.PyThreadState_SetAsyncExc(tid, None)
            raise SystemError("PyThreadState_SetAsyncExc failed")

    def terminate(self):
        for worker in self.__workers:
            if not worker.is_die():
                try:
                    self._async_raise(worker.ident, SystemExit)
                except Exception as e:
                    print(f"not right kill:{e}")

    def join(self):
        for work in self.__workers:
            work.join()

    def run_async(self, tasks, callback=None):
        tasks_block = data_block(tasks, len(self.__workers))
        for i in range(len(self.__workers)):
            self.__workers[i].tasks = tasks_block[i]
            self.__workers[i].callback = callback
            self.__workers[i].setDaemon(True)

        for worker in self.__workers:
            worker.start()


class _Parallelism(metaclass=abc.ABCMeta):

    def __init__(self, executor=multiprocessing.cpu_count(), mode='all'):
        self._executor = executor  # cpu核心数量
        self._mode = mode

    @abc.abstractmethod
    def get_result(self):
        pass

    @property
    @abc.abstractmethod
    def progress(self):
        pass

    @abc.abstractmethod
    def run(self, func):
        """外部调用接口,启动执行器"""
        pass

    @abc.abstractmethod
    def terminate(self):
        pass


class ProcessExecutor(_Parallelism):

    def __init__(self, executor=multiprocessing.cpu_count(), mode='all'):
        super(ProcessExecutor, self).__init__(executor, mode)
        self.__pool = multiprocessing.Pool(processes=self._executor)
        self.__results = multiprocessing.Queue()
        self.__task_count = 0

    def get_result(self):
        if self.__results.qsize() < 1:
            print(
                "Executor result is none, may be not produce or has been read")
            return
        if self._mode == 'first':
            return self.__results.get()
        else:
            if self.progress == 1:
                out = []
                for _ in range(self.__results.qsize()):
                    out.append(self.__results.get())
                return out
            else:
                print(
                    f"has not all completed, process:{self.progress}， please wait!"
                )

    @property
    def progress(self):
        return round(self.__results.qsize() / self.__task_count, 2)

    def __complete(self, result):
        try:
            self.__results.put(result, timeout=3)
            if self.progress == 1:
                self.__pool.terminate()
            # print(f"one task complete, has finished: {self.progress}")
        except Exception as e:
            print(e)

    @staticmethod
    def __exception(e):
        print(e)

    def run(self, tasks):
        if hasattr(self, "__run_flag"):
            print("one executor, 'run' only can run once")
            return
        else:
            setattr(self, "__run_flag", True)

        self.__task_count = len(tasks)
        for task in tasks:
            self.__pool.apply_async(func=task,
                                    callback=self.__complete,
                                    error_callback=ProcessExecutor.__exception)
        if self._mode == "all":
            self.__pool.close()
            self.__pool.join()
        elif self._mode == "first":
            self.__results.put(self.__results.get())
            self.__pool.terminate()

    def terminate(self):
        self.__pool.terminate()


class ThreadExecutor(_Parallelism):

    def __init__(self, executor=multiprocessing.cpu_count(), mode='all'):
        """

        :param executor:
        :param mode: all | first | async
        """
        super(ThreadExecutor, self).__init__(executor, mode)
        self.__pool = _MyThreadPool(max_worker=self._executor)
        self.__results = queue.Queue()
        self.__task_count = 0

    def get_result(self):
        if self.__results.qsize() < 1:
            print(
                "Executor result is none, may be not produce or has been read")
            return
        if self._mode == 'first':
            return self.__results.get()
        else:
            if self.progress == 1:
                out = []
                for _ in range(self.__results.qsize()):
                    out.append(self.__results.get())
                return out
            else:
                print(
                    f"has not all completed, process:{self.progress}， please wait!"
                )

    @property
    def progress(self):
        return round(self.__results.qsize() / self.__task_count, 2)

    def __complete(self, result):
        try:
            self.__results.put(result, timeout=3)
            # print(f"one task complete, has finished: {self.progress}")
        except Exception as e:
            print(e)

    def run(self, tasks):
        if hasattr(self, "__run_flag"):
            print("one executor, 'run' can only run once")
            return
        else:
            setattr(self, "__run_flag", True)

        self.__task_count = len(tasks)
        self.__pool.run_async(tasks=tasks, callback=self.__complete)
        if self._mode == "all":
            self.__pool.join()
        elif self._mode == "first":
            self.__results.put(self.__results.get())
            self.__pool.terminate()

    def terminate(self):
        self.__pool.terminate()


class AsyncExecutor(_Parallelism):

    def __init__(self, mode='all'):
        super(AsyncExecutor, self).__init__(0, mode)  # 第一个参数在协程中是没有用到的
        self.__loop = asyncio.get_event_loop()
        self.__results = queue.Queue()
        self.__task_count = 0

    def get_result(self):
        if self.__results.qsize() < 1:
            print(
                "Executor result is none, may be not produce or has been read")
            return
        if self._mode == 'first':
            return self.__results.get()
        else:
            if self.progress == 1:
                out = []
                for _ in range(self.__results.qsize()):
                    out.append(self.__results.get())
                return out
            else:
                print(
                    f"has not all completed, process:{self.progress}， please wait!"
                )

    @property
    def progress(self):
        return round(self.__results.qsize() / self.__task_count, 2)

    def __complete(self, future: asyncio.Future):
        try:
            self.__results.put(future.result(), timeout=3)
            # print(f"one task complete, has finished: {self.progress}")
        except Exception as e:
            if type(e) is asyncio.CancelledError:
                print("CancelledError", e)
            else:
                print(e)

    def run(self, tasks):
        if hasattr(self, "__run_flag"):
            print("one executor, 'run' can only run once")
            return
        else:
            setattr(self, "__run_flag", True)

        self.__task_count = len(tasks)
        tasks: List[asyncio.Future] = [asyncio.ensure_future(t) for t in tasks]
        for task in tasks:
            task.add_done_callback(self.__complete)
        if self._mode == "all":
            self.__loop.run_until_complete(asyncio.wait(tasks))
        elif self._mode == "first":
            _, undone = self.__loop.run_until_complete(
                asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED))
            for task in undone:
                task.cancel()
            try:
                self.__loop.run_until_complete(
                    asyncio.gather(*tasks, return_exceptions=True))
            except asyncio.CancelledError:
                print("AsyncExecutor cancel")
        self.__loop.close()

    def terminate(self):
        pass
