import telebot
from web3 import Web3
from eth_account.messages import encode_defunct
import json
import os
import time
import threading
import random
import string

# Ethereum Configuration
ETH_NODE_URL = os.getenv("ETH_NODE_URL")  # Replace with your Ethereum node URL
CONTRACT_ADDRESS = os.getenv("CONTRACT_ADDRESS")  # Replace with your deployed contract address
PRIVATE_KEY = os.getenv("BOT_PRIVATE_KEY")  # Replace with your bot's wallet private key
BOT_ADDRESS = Web3.to_checksum_address(os.getenv("BOT_WALLET_ADDRESS"))  # Replace with your bot's wallet address
TOKEN_ADDRESS = CONTRACT_ADDRESS  # Replace with your CasinoToken contract address
BALANCE_STORAGE = os.getenv("BALANCE_STORAGE")

TOKENS_TO_ROLL = 10

web3 = Web3(Web3.HTTPProvider(ETH_NODE_URL))

# Load contract ABI
with open("SemaphoreToken.json", "r") as abi_file:
    CONTRACT_ABI = json.load(abi_file)

contract = web3.eth.contract(address=Web3.to_checksum_address(CONTRACT_ADDRESS), abi=CONTRACT_ABI["abi"])
owner = contract.functions.owner().call()
rate = contract.functions.exchangeRate().call()
nonce = web3.eth.get_transaction_count(BOT_ADDRESS)

active_users_lock = threading.Lock()
active_users = set()

print(f"owner: {owner}, rate: {rate}")

# Telegram bot setup
bot = telebot.TeleBot(os.getenv("TELEGRAM_BOT_TOKEN"))

# Dictionary to store Telegram username -> wallet address mapping
user_wallets = {}
if os.path.exists("users.json"):
    with open("users.json", "r") as users_file:
        user_wallets = json.load(users_file)

def dump_users(addresses):
    with open("users.json", "w") as users_file:
        json.dump(addresses, users_file, indent=4)


dice_coefs = {
    '🎲': [0, 0.3, 0.5, 1, 1.6, 2],
    '🏀': [0, 0, 0.5, 2, 2],
    '⚽️': [0, 0, 1.5, 1.5, 1.5],
    '🎯': [0, 0.1, 0.3, 0.5, 1.5, 3],
    '🎳': [0, 0.1, 0.3, 1, 1.5, 2.5],
    '🎰': [0 for i in range(64)]
}


dice_coefs['🎰'][0] = 9 # bar x3
dice_coefs['🎰'][63] = 30 # 777
dice_coefs['🎰'][21] = 9 # grape x3
dice_coefs['🎰'][42] = 9 # lemon x3

pending_verifications = {}


@bot.message_handler(commands=["start"])
def start(message):
    bot.reply_to(message, "Welcome to the Casino Bot! Use /register <your_wallet_address> to deposit CasinoToken and start playing.")


@bot.message_handler(commands=["register"])
def register(message):
    user = message.from_user
    args = message.text.split()

    if len(args) != 2:
        bot.reply_to(message, "Please provide your wallet address. Usage: /register <your_wallet_address>")
        return

    wallet_address = args[1]
    if not Web3.is_checksum_address(wallet_address):
        bot.reply_to(message, "Invalid wallet address. Please provide a valid Ethereum address.")
        return

    random_message = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
    pending_verifications[user.username] = (wallet_address, random_message)

    bot.reply_to(
        message,
        f"To verify your ownership of the wallet, sign the following message with your wallet and send the signature:\n\n`{random_message}`\n\nUse any Ethereum wallet to sign this message (for example use [this](https://etherscan.io/verifiedSignatures)) and send the signature back with the command `/verify <signature>`.",
        parse_mode="markdown"
    )


@bot.message_handler(commands=["verify"])
def verify(message):
    user = message.from_user
    args = message.text.split()

    if len(args) != 2:
        bot.reply_to(message, "Please provide your signature. Usage: /verify <signature>")
        return

    signature = args[1]

    if user.username not in pending_verifications:
        bot.reply_to(message, "No pending verification found. Use /register to start the process.")
        return

    wallet_address, random_message = pending_verifications[user.username]

    try:
        recovered_address = web3.eth.account.recover_message(encode_defunct(text=random_message), signature=signature)

        if recovered_address.lower() == wallet_address.lower():
            user_wallets[user.username] = wallet_address
            dump_users(user_wallets)

            bot.reply_to(message, f"Verification successful! Your wallet address {wallet_address} has been registered.")
            del pending_verifications[user.username]
        else:
            bot.reply_to(message, "Verification failed. The signature does not match the wallet address.")
    except Exception as e:
        bot.reply_to(message, f"An error occurred during verification: {str(e)}")


@bot.message_handler(commands=["balance"])
def balance(message):
    user, wallet_address = login(message)
    if not user or not wallet_address:
        return

    balance = contract.functions.balanceOf(wallet_address).call()

    balance_msg = f"Your SemaphoreToken balance: {balance} SMPH's, {balance // TOKENS_TO_ROLL} rolls\n"
    balance_msg += f"Send ETH (0.005 ETH = 1 SMPH, 10 SMPH = 1 roll) to the following address to start playing: {CONTRACT_ADDRESS}"

    bot.reply_to(message, balance_msg)


@bot.message_handler(commands=["roll_dice"])
def roll_dice(message):
    message.text = '/roll 🎲'
    return roll(message)


@bot.message_handler(commands=["roll_basket"])
def roll_basket(message):
    message.text = '/roll 🏀'
    return roll(message)


@bot.message_handler(commands=["roll_goll"])
def roll_goll(message):
    message.text = '/roll ⚽️'
    return roll(message)


@bot.message_handler(commands=["roll_darts"])
def roll_darts(message):
    message.text = '/roll 🎯'
    return roll(message)


@bot.message_handler(commands=["roll_bowling"])
def roll_bowling(message):
    message.text = '/roll 🎳'
    return roll(message)


@bot.message_handler(commands=["roll_kazik"])
def roll_kazik(message):
    message.text = '/roll 🎰'
    return roll(message)


@bot.message_handler(commands=["roll"])
def roll(message):
    user, wallet_address = login(message)
    if not user or not wallet_address:
        return
    if not add_user(wallet_address):
        bot.reply_to(message, "Please do not hurry, previous transaction is running...")
        return

    args = message.text.split()
    if len(args) != 2:
        bot.reply_to(message, "Please provide casino type as an emoji. Examples: 🎲, 🏀")
        remove_user(wallet_address)
        return

    emoji = args[1]
    if emoji not in dice_coefs:
        bot.reply_to(message, f"Unsupportable emoji provided. Avalable emojies: {', '.join(dice_coefs.keys())}")
        remove_user(wallet_address)
        return
    coefs = dice_coefs[emoji]

    balance = contract.functions.balanceOf(wallet_address).call()

    if balance < TOKENS_TO_ROLL:
        not_enough_bal_msg = f"You have no balance. Deposit more ETH to roll!!! Current balance {balance}\n"
        not_enough_bal_msg += f"Send ETH (0.005 ETH = 1 SMPH, 10 SMPH = 1 roll) to the following address to start playing: {CONTRACT_ADDRESS}"

        bot.reply_to(message, not_enough_bal_msg)
        remove_user(wallet_address)
        return

    dice_response = bot.send_dice(message.chat.id, emoji=emoji, reply_to_message_id=message.id)
    dice_roll = dice_response.dice.value

    payout = int(coefs[dice_roll - 1] * TOKENS_TO_ROLL)
    tx_hash = None

    try:
        if payout - TOKENS_TO_ROLL > 0:
            tx_hash = send_token(CONTRACT_ADDRESS, wallet_address, payout - TOKENS_TO_ROLL)
            bot.reply_to(message, f"You win {payout} SMPH! The prize will be sent as soon as possible. [tx](https://sepolia.etherscan.io/tx/0x{tx_hash.hex()})", disable_web_page_preview=True, parse_mode="markdown")
        elif TOKENS_TO_ROLL - payout > 0:
            tx_hash = send_token(wallet_address, CONTRACT_ADDRESS, TOKENS_TO_ROLL - payout)
            bot.reply_to(message, f"No payout this time. Cashback: {payout} SMPH. Better luck next roll!")
        else:
            bot.reply_to(message, f"No payout this time. Cashback: {TOKENS_TO_ROLL} SMPH. Better luck next roll!")

        tx_receipt = get_tx_receipt(tx_hash)
        if tx_receipt['status'] != 1:
            bot.reply_to(message, "!!! alarm, previous transaction failed !!!")
    except Exception as e:
        bot.reply_to(message, f"An error occurred during transaction: {str(e)}")
    remove_user(wallet_address)


@bot.message_handler(commands=["withdraw"])
def withdraw(message):
    user, wallet_address = login(message)
    if not user or not wallet_address:
        return
    if not add_user(wallet_address):
        bot.reply_to(message, "Please do not hurry, previous transaction is running...")
        return

    args = message.text.split()

    if len(args) != 2:
        bot.reply_to(message, "Please provide your withdraw amount. Usage: /withdraw <amount of SMPH tokens>")
        remove_user(wallet_address)
        return

    if not args[1].isdigit():
        bot.reply_to(message, "Amount of tokens must be integer")
        remove_user(wallet_address)
        return
    withdraw_amount = int(args[1])

    balance = contract.functions.balanceOf(wallet_address).call()
    if balance < withdraw_amount:
        not_enough_bal_msg = f"You don't have enough money to withdraw {withdraw_amount}.\nCurrent balance: {balance}\n"
        bot.reply_to(message, not_enough_bal_msg)
        remove_user(wallet_address)
        return

    tx_hash = withdraw_tokens(wallet_address, withdraw_amount)
    bot.reply_to(message, f"Withdraw success! The ETH will be sent as soon as possible. [tx](https://sepolia.etherscan.io/tx/0x{tx_hash.hex()})", disable_web_page_preview=True, parse_mode="markdown")
    remove_user(wallet_address)


def login(message):
    user = message.from_user
    wallet_address = user_wallets.get(user.username)

    if not wallet_address:
        bot.reply_to(message, "You have not registered your wallet address. Use /register <your_wallet_address> to register.")
        return None, None

    return user, wallet_address


def get_tx_receipt(tx_hash):
    if tx_hash is None:
        return {'status': 1}

    transaction_receipt = None
    while transaction_receipt is None:
        try:
            transaction_receipt = web3.eth.get_transaction_receipt(tx_hash)
        except:
            pass
        time.sleep(0.1)
    return transaction_receipt


def send_token(sender, receiver, amount):
    global nonce
    tx = contract.functions.privilegedTransfer(sender, receiver, amount).build_transaction({
        'from': owner,
        'chainId': web3.eth.chain_id,
        'nonce': nonce
    })
    nonce += 1

    signed_tx = web3.eth.account.sign_transaction(tx, private_key=PRIVATE_KEY)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.raw_transaction)

    return tx_hash


def withdraw_tokens(receiver, amount):
    global nonce
    tx = contract.functions.exchangeTokens(amount, receiver).build_transaction({
        'from': owner,
        'chainId': web3.eth.chain_id,
        'nonce': nonce
    })
    nonce += 1

    signed_tx = web3.eth.account.sign_transaction(tx, private_key=PRIVATE_KEY)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.raw_transaction)

    return tx_hash


def add_user(wallet):
    global active_users_lock
    global active_users

    with active_users_lock:
        if wallet in active_users:
            return False
        active_users.add(wallet)
        return True


def remove_user(wallet):
    global active_users_lock
    global active_users

    with active_users_lock:
        active_users.discard(wallet)


bot.polling()
