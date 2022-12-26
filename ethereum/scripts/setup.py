from setuptools import setup
from os import path

here = path.abspath(path.dirname(__file__))

setup(
    name='dola-ethereum-sdk',
    version='0.0.1',
    description='Dola ETHEREUM SDK',
    # The project's main homepage.
    url='https://github.com/OmniBTC/DolaProtocol/blob/main/ethereum/scripts/dola_ethereum_sdk',
    # Author details
    author='DaiWei',
    author_email='dw1253464613@gmail.com',
    # Choose your license
    license='MIT',
    classifiers=[
        'Development Status :: 4 - Beta',
        'Intended Audience :: Developers',
        'Topic :: System :: Logging',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.3',
        'Programming Language :: Python :: 3.4',
        'Programming Language :: Python :: 3.5',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
    ],
    python_requires=">=3.6",
    package_data={'': ['*']},
    packages=["dola_ethereum_sdk"],
    install_requires=["eth-brownie"]
)
