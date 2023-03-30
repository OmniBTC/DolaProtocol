# @Time    : 2023/3/30 10:32
# @Author  : WeiDai
# @FileName: transaction.py


class TransactionBuilder:
    """
    example:
    1. function:
        public fun owner(counter: &Counter): address {
            counter.owner
        }
        abi:
        {'visibility': 'Public', 'isEntry': False, 'typeParameters': [], 'parameters': [{'Reference':
        {'Struct': {'address': '0x1b57e5fd1bf38dd5d3249d66cabf975f64c2ce04e876ba66d1cd48a50a7c8a49',
        'module': 'counter', 'name': 'Counter', 'typeArguments': []}}}], 'return': ['Address'],
        'module_name': 'counter', 'func_name': 'owner'}
    """
    def move_call(
            self,
            signer,
            abi,
            type_args,
            call_args,
            gas,
            gas_budget,
    ):
        pass
