# Overview

This is an sui python tool to quickly implement sui calls.



# Publish

~~~shell
python setup.py bdist_wheel

twine upload --verbose  --repository upload  dist/*
~~~



# Setup

~~~shell
pip install sui_brownie
~~~



# Import

~~~python
import sui_brownie

package = sui_brownie.SuiPackage(
				 				 brownie_config: Union[Path, str] = Path.cwd(),
                 network: str = "sui-devnet",
                 is_compile: bool = True,
                 package_id: str = None,
                 package_path: Union[Path, str] = None)
~~~



# Publish

~~~python
package.publish_package(replace_address=dict(serde="0x1234", wormhole="0x2345"))
~~~



# Simulate

~~~
package.{module_name}.{func_name}.simulate(10)
~~~



# Call

~~~python
package.{module_name}.{func_name}(10)
~~~



# CacheObject

1. From package

~~~python
# list
package.{module_name}.{struct_name}
~~~

2. From global

~~~
from sui_brownie import CacheObject

# dict, ObjectType --> list
CacheObject.{module_name}.{struct_name}
~~~

