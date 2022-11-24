# Overview

This is an sui python tool to quickly implement sui calls.



# Setup

~~~shell
pip install sui_brownie
~~~



# Use

~~~python
import sui_brownie

package = sui_brownie.SuiPackage(
  project_path=omniswap_sui_path,
  network=net
)

package["so_fee_wormhole::initialize"](2)
~~~

