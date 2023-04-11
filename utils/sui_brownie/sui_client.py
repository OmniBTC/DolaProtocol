from retrying import retry
import httpx


class ApiError(Exception):
    """Error thrown when the API returns >= 400"""

    def __init__(self, message, status_code):
        # Call the base class constructor with the parameters it needs
        super().__init__(message)
        self.status_code = status_code


class SuiClient(httpx.Client):
    def __init__(self, base_url, timeout):
        super(SuiClient, self).__init__(base_url=base_url, timeout=timeout)
        self.endpoint = base_url

    @retry(stop_max_attempt_number=5, wait_random_min=500, wait_random_max=1000)
    def get(self, *args, **kwargs):
        return super().get(*args, **kwargs)

    @retry(stop_max_attempt_number=5, wait_random_min=500, wait_random_max=1000)
    def post(self, *args, **kwargs):
        response = super().post(*args, **kwargs)
        if response.status_code >= 400:
            raise ApiError(response.text, response.status_code)
        return response

    def sui_devInspectTransactionBlock(
            self,
            sender_address,
            tx_bytes,
            gas_price,
            epoch,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_devInspectTransactionBlock",
                "params": [
                    sender_address,
                    tx_bytes,
                    gas_price,
                    epoch
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_dryRunTransactionBlock(
            self,
            tx_bytes,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_dryRunTransactionBlock",
                "params": [
                    tx_bytes,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_executeTransactionBlock(
            self,
            tx_bytes,
            signatures,
            options,
            request_type,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_executeTransactionBlock",
                "params": [
                    tx_bytes,
                    signatures,
                    options,
                    request_type,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getCheckpoint(
            self,
            cid
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getCheckpoint",
                "params": [
                    cid
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getCheckpoints(
            self,
            cursor,
            limit,
            descending_order,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getCheckpoints",
                "params": [
                    cursor,
                    limit,
                    descending_order,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getEvents(
            self,
            transaction_digest,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getEvents",
                "params": [
                    transaction_digest
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getLatestCheckpointSequenceNumber(
            self,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getLatestCheckpointSequenceNumber",
                "params": [
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getMoveFunctionArgTypes(
            self,
            package,
            module,
            function,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getMoveFunctionArgTypes",
                "params": [
                    package,
                    module,
                    function,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getNormalizedMoveFunction(
            self,
            package,
            module_name,
            function_name,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getNormalizedMoveFunction",
                "params": [
                    package,
                    module_name,
                    function_name,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getNormalizedMoveModule(
            self,
            package,
            module_name,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getNormalizedMoveModule",
                "params": [
                    package,
                    module_name,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getNormalizedMoveModulesByPackage(
            self,
            package
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getNormalizedMoveModulesByPackage",
                "params": [
                    package
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getNormalizedMoveStruct(
            self,
            package,
            module_name,
            struct_name,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getNormalizedMoveStruct",
                "params": [
                    package,
                    module_name,
                    struct_name,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getObject(
            self,
            object_id,
            options,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getObject",
                "params": [
                    object_id,
                    options,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getTotalTransactionBlocks(
            self,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getTotalTransactionBlocks",
                "params": [
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_getTransactionBlock(
            self,
            digest,
            options,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getTransactionBlock",
                "params": [
                    digest,
                    options,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_multiGetObjects(
            self,
            object_ids,
            options,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_multiGetObjects",
                "params": [
                    object_ids,
                    options,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_multiGetTransactionBlocks(
            self,
            digests,
            options,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_multiGetTransactionBlocks",
                "params": [
                    digests,
                    options,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_tryGetPastObject(
            self,
            object_id,
            version,
            options,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_tryGetPastObject",
                "params": [
                    object_id,
                    version,
                    options,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def sui_tryMultiGetPastObjects(
            self,
            past_objects,
            options,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_tryMultiGetPastObjects",
                "params": [
                    past_objects,
                    options,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getAllBalances(
            self,
            owner,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getAllBalances",
                "params": [
                    owner
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getAllCoins(
            self,
            owner,
            cursor,
            limit,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getAllCoins",
                "params": [
                    owner,
                    cursor,
                    limit,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getBalance(
            self,
            owner,
            coin_type,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getBalance",
                "params": [
                    owner,
                    coin_type,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getCoinMetadata(
            self,
            coin_type,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getCoinMetadata",
                "params": [
                    coin_type,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getCoins(
            self,
            owner,
            coin_type,
            cursor,
            limit,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getCoins",
                "params": [
                    owner,
                    coin_type,
                    cursor,
                    limit,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getCommitteeInfo(
            self,
            epoch
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getCommitteeInfo",
                "params": [
                    epoch
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getCurrentEpoch(
            self,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getCurrentEpoch",
                "params": [
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getDynamicFieldObject(
            self,
            parent_object_id,
            name,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getDynamicFieldObject",
                "params": [
                    parent_object_id,
                    name,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getDynamicFields(
            self,
            parent_object_id,
            name,
            limit
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getDynamicFields",
                "params": [
                    parent_object_id,
                    name,
                    limit
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getEpochs(
            self,
            cursor,
            limit,
            descending_order,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getEpochs",
                "params": [
                    cursor,
                    limit,
                    descending_order,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getLatestSuiSystemState(
            self,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getLatestSuiSystemState",
                "params": [
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getMoveCallMetrics(
            self,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getMoveCallMetrics",
                "params": [
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getNetworkMetrics(
            self,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getNetworkMetrics",
                "params": [
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getOwnedObjects(
            self,
            address,
            query,
            cursor,
            limit,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getOwnedObjects",
                "params": [
                    address,
                    query,
                    cursor,
                    limit,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getReferenceGasPrice(
            self
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getReferenceGasPrice",
                "params": [
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getStakes(
            self,
            owner
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getStakes",
                "params": [
                    owner
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getStakesByIds(
            self,
            staked_sui_ids,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getStakesByIds",
                "params": [
                    staked_sui_ids,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_getTotalSupply(
            self,
            coin_type,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_getTotalSupply",
                "params": [
                    coin_type,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_queryEvents(
            self,
            query,
            cursor,
            limit,
            descending_order,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_queryEvents",
                "params": [
                    query,
                    cursor,
                    limit,
                    descending_order,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_queryObjects(
            self,
            query,
            cursor,
            limit,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_queryObjects",
                "params": [
                    query,
                    cursor,
                    limit,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_queryTransactionBlocks(
            self,
            query,
            cursor,
            limit,
            descending_order,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_queryTransactionBlocks",
                "params": [
                    query,
                    cursor,
                    limit,
                    descending_order,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def suix_subscribeEvent(
            self,
            sender_address,
            tx_bytes,
            gas_price,
            epoch,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "suix_subscribeEvent",
                "params": [
                    sender_address,
                    tx_bytes,
                    gas_price,
                    epoch
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_batchTransaction(
            self,
            signer,
            single_transaction_params,
            gas,
            gas_budget,
            txn_builder_mode,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_batchTransaction",
                "params": [
                    signer,
                    single_transaction_params,
                    gas,
                    gas_budget,
                    txn_builder_mode,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_mergeCoins(
            self,
            signer,
            primary_coin,
            coin_to_merge,
            gas,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_mergeCoins",
                "params": [
                    signer,
                    primary_coin,
                    coin_to_merge,
                    gas,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_moveCall(
            self,
            signer,
            package_object_id,
            module,
            function,
            type_arguments,
            arguments,
            gas,
            gas_budget,
            execution_mode
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_moveCall",
                "params": [
                    signer,
                    package_object_id,
                    module,
                    function,
                    type_arguments,
                    arguments,
                    gas,
                    gas_budget,
                    execution_mode
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_pay(
            self,
            signer,
            input_coins,
            recipients,
            amounts,
            gas,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_pay",
                "params": [
                    signer,
                    input_coins,
                    recipients,
                    amounts,
                    gas,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_payAllSui(
            self,
            signer,
            input_coins,
            recipient,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_payAllSui",
                "params": [
                    signer,
                    input_coins,
                    recipient,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_paySui(
            self,
            signer,
            input_coins,
            recipients,
            amounts,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_paySui",
                "params": [
                    signer,
                    input_coins,
                    recipients,
                    amounts,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_publish(
            self,
            sender,
            compiled_modules,
            dependencies,
            gas,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_publish",
                "params": [
                    sender,
                    compiled_modules,
                    dependencies,
                    gas,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_requestAddStake(
            self,
            signer,
            coins,
            amount,
            validator,
            gas,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_requestAddStake",
                "params": [
                    signer,
                    coins,
                    amount,
                    validator,
                    gas,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_requestWithdrawStake(
            self,
            signer,
            staked_sui,
            gas,
            gas_budget,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_requestWithdrawStake",
                "params": [
                    signer,
                    staked_sui,
                    gas,
                    gas_budget,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_splitCoin(
            self,
            signer,
            coin_object_id,
            split_amounts,
            gas,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_splitCoin",
                "params": [
                    signer,
                    coin_object_id,
                    split_amounts,
                    gas,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_splitCoinEqual(
            self,
            signer,
            coin_object_id,
            split_count,
            gas,
            gas_budget
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_splitCoinEqual",
                "params": [
                    signer,
                    coin_object_id,
                    split_count,
                    gas,
                    gas_budget
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_transferObject(
            self,
            signer,
            object_id,
            gas,
            gas_budget,
            recipient,
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_transferObject",
                "params": [
                    signer,
                    object_id,
                    gas,
                    gas_budget,
                    recipient,
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]

    def unsafe_transferSui(
            self,
            signer,
            sui_object_id,
            gas_budget,
            recipient,
            amount
    ):
        response = self.post(
            f"{self.endpoint}",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "unsafe_transferSui",
                "params": [
                    signer,
                    sui_object_id,
                    gas_budget,
                    recipient,
                    amount
                ]
            },
        )
        response = response.json()
        assert "error" not in response, response
        return response["result"]
