# Overview

This is an sui python tool to quickly implement sui deployment, call and etc.



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
sui_project = self.load_project()
sui_project.active_account("Relayer")
math = SuiPackage(package_path=Path.cwd().joinpath("TestProject/math"))
~~~



# Publish

~~~python
math.publish_package(replace_address=dict())
# or 
math.program_publish_package(replace_address=dict())
~~~



# Simulate

~~~
{package_name}.{module_name}.{func_name}.simulate(10)
~~~



# Call

~~~
{package_name}.{module_name}.{func_name}(10)
~~~



# Cache

1. From package

~~~
# list
{package_name}.{module_name}.{struct_name}
~~~

2. From project

~~~
# dict, SuiObject --> list
sui_projcet.{package_name}
~~~

