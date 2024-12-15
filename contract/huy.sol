// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SemaphoreToken {
    // Событие для фиксации поступивших транзакций
    event Received(address indexed sender, uint amount);
    event TokensPurchased(address indexed purchaser, uint amount);
    event TokensExchanged(address indexed exchanger, uint ethAmount);
    event TokensBalanceAdjusted(address indexed user, uint newBalance);
    event TokensBalanceChanged(address indexed user, int changeAmount, uint newBalance);

    address public owner;
    uint public exchangeRate; // Количество SemaphoreToken за 1 ETH

    mapping(address => uint) public balancesToken;

    constructor(uint _exchangeRate) {
        owner = msg.sender;
        exchangeRate = _exchangeRate;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    receive() external payable {
        // Вычислить количество токенов для выдачи
        uint tokenAmount = msg.value * exchangeRate;

        // Обновить баланс токенов отправителя
        balancesToken[msg.sender] += tokenAmount;
        
        // Зафиксировать получение средств и выдачу токенов
        emit Received(msg.sender, msg.value);
        emit TokensPurchased(msg.sender, tokenAmount);
    }

    function setExchangeRate(uint newRate) public onlyOwner {
        exchangeRate = newRate;
    }

    function exchangeTokens(uint tokenAmount, address payable recipient) public onlyOwner {
        // Проверка, достаточно ли токенов у вызывающего
        require(balancesToken[msg.sender] >= tokenAmount, "Insufficient tokens to exchange");

        // Вычислить количество эфира для возврата
        uint etherAmount = tokenAmount / exchangeRate;

        // Проверка, достаточно ли эфира в контракте для обмена
        require(address(this).balance >= etherAmount, "Contract has insufficient Ether");

        // Обновить баланс токенов вызывающего
        balancesToken[msg.sender] -= tokenAmount;

        // Перевести эфир
        recipient.transfer(etherAmount);

        emit TokensExchanged(msg.sender, etherAmount);
    }

    function getTokenBalance(address addr) public view returns (uint) {
        return balancesToken[addr];
    }

    function mintTokens(address to, uint amount) public onlyOwner {
        balancesToken[to] += amount;
    }

    function adjustTokenBalance(address user, uint newBalance) public onlyOwner {
        balancesToken[user] = newBalance;
        emit TokensBalanceAdjusted(user, newBalance);
    }

    function changeTokenBalance(address user, int changeAmount) public onlyOwner {
        // Предполагаем, что изменение может быть как положительным, так и отрицательным
        if (changeAmount > 0) {
            balancesToken[user] += uint(changeAmount);
        } else {
            uint decreaseAmount = uint(-changeAmount);
            require(balancesToken[user] >= decreaseAmount, "Insufficient balance to decrease");
            balancesToken[user] -= decreaseAmount;
        }
        emit TokensBalanceChanged(user, changeAmount, balancesToken[user]);
    }
}
