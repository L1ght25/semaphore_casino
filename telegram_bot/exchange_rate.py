import telebot
from web3 import Web3
import json
import os

# Ethereum Configuration
ETH_NODE_URL = os.getenv("ETH_NODE_URL")  # Replace with your Ethereum node URL
CONTRACT_ADDRESS = os.getenv("CONTRACT_ADDRESS")  # Replace with your deployed contract address
PRIVATE_KEY = os.getenv("BOT_PRIVATE_KEY")  # Replace with your bot's wallet private key
BOT_ADDRESS = Web3.to_checksum_address(os.getenv("BOT_WALLET_ADDRESS"))  # Replace with your bot's wallet address
TOKEN_ADDRESS = CONTRACT_ADDRESS  # Replace with your CasinoToken contract address

web3 = Web3(Web3.HTTPProvider(ETH_NODE_URL))

# Load contract ABI
with open("SemaphoreToken.json", "r") as abi_file:
    CONTRACT_ABI = json.load(abi_file)

contract = web3.eth.contract(address=Web3.to_checksum_address(CONTRACT_ADDRESS), abi=CONTRACT_ABI["abi"])
owner = contract.functions.owner().call()
nonce = web3.eth.get_transaction_count(BOT_ADDRESS)

# Telegram bot setup
bot = telebot.TeleBot(os.getenv("TELEGRAM_BOT_TOKEN"))

tx = contract.functions.setExchangeRate(int(5e15)).build_transaction({
        'from': owner,
        'chainId': web3.eth.chain_id,
        'nonce': nonce
    })

signed_tx = web3.eth.account.sign_transaction(tx, private_key=PRIVATE_KEY)
tx_hash = web3.eth.send_raw_transaction(signed_tx.raw_transaction)
print(tx_hash)