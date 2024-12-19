// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";


contract BalancesStorage {
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    address public ownerContractAddress;

    modifier onlyOwner() {
        require(msg.sender == ownerContractAddress, "Only owner can call this function");
        _;
    }

    constructor(address _ownerContractAddress) {
        require(_ownerContractAddress != address(0), "Owner address cannot be zero");
        ownerContractAddress = _ownerContractAddress;
    }

    // Функция для увеличения баланса
    function increaseBalance(address account, uint256 amount) public onlyOwner {
        require(account != address(0), "Account cannot be zero address");
        balances[account] += amount;
    }

    // Функция для уменьшения баланса
    function decreaseBalance(address account, uint256 amount) public onlyOwner {
        require(account != address(0), "Account cannot be zero address");
        require(balances[account] >= amount, "Insufficient balance");
        balances[account] -= amount;
    }

    // Функция для перевода средств между аккаунтами
    function privilegedTransfer(address from, address to, uint256 amount) public onlyOwner {
        require(from != address(0) && to != address(0), "Addresses cannot be zero address");
        require(balances[from] >= amount, "Insufficient balance");
        balances[from] -= amount;
        balances[to] += amount;
    }
    
    // Функция для передачи права владения
    function transferOwnership(address newOwnerContractAddress) public onlyOwner {
        require(newOwnerContractAddress != address(0), "New owner address cannot be zero");
        ownerContractAddress = newOwnerContractAddress;
    }

    // Функция для получения баланса аккаунта
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function allowanceOf(address from, address to) public view returns (uint256) {
        return allowances[from][to];
    }

    function setAllowance(address from, address to, uint256 amount) public onlyOwner {
        allowances[from][to] = amount;
    }

}

contract SemaphoreToken is IERC20 {
    // События для ERC20
    // event Transfer(address indexed from, address indexed to, uint256 value);
    // event Approval(address indexed owner, address indexed spender, uint256 value);

    // Дополнительные события
    event Received(address indexed sender, uint256 amount);
    event TokensPurchased(address indexed purchaser, uint256 amount);
    event TokensExchanged(address indexed exchanger, uint256 ethAmount);

    address public owner;
    uint256 public exchangeRate; // Количество wei за 1 SMPH

    BalancesStorage bs;

    uint256 private totalSupply_;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor(uint256 _exchangeRate, uint256 initialSupply, address _balancesStorage) {
        owner = msg.sender;
        exchangeRate = _exchangeRate;
        totalSupply_ = initialSupply;
        bs = BalancesStorage(_balancesStorage);
        // we are not owner right now
    }

    function name() public pure returns (string memory) {
        return "SemaphoreToken";
    }

    function symbol() public pure returns (string memory) {
        return "SMPH";
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return bs.balanceOf(account);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view override returns (uint256) {
        return bs.allowanceOf(_owner, spender);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, bs.allowanceOf(sender, msg.sender) - amount);
        return true;
    }

    function privilegedTransfer(address from, address to, uint256 amount) public onlyOwner {
        _transfer(from, to, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(bs.balanceOf(sender) >= amount, "ERC20: transfer amount exceeds balance");

        bs.decreaseBalance(sender, amount);
        bs.increaseBalance(sender, amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        totalSupply_ += amount;
        bs.increaseBalance(account, amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        require(bs.balanceOf(account) >= amount, "ERC20: burn amount exceeds balance");

        bs.decreaseBalance(account, amount);
        totalSupply_ -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address _owner, address spender, uint256 amount) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        bs.setAllowance(_owner, spender, amount);
        emit Approval(_owner, spender, amount);
    }

    receive() external payable {
        uint256 tokenAmount = msg.value / exchangeRate;
        _mint(msg.sender, tokenAmount);
        
        emit Received(msg.sender, msg.value);
        emit TokensPurchased(msg.sender, tokenAmount);
    }

    function setExchangeRate(uint256 newRate) public onlyOwner {
        exchangeRate = newRate;
    }

    function exchangeTokens(uint256 tokenAmount, address payable recipient) public {
        require(bs.balanceOf(msg.sender) >= tokenAmount, "Insufficient tokens to exchange");
        uint256 etherAmount = tokenAmount * exchangeRate;
        require(address(this).balance >= etherAmount, "Contract has insufficient Ether");

        _burn(msg.sender, tokenAmount);
        recipient.transfer(etherAmount);

        emit TokensExchanged(msg.sender, etherAmount);
    }
}

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        uint pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);

        vm.startBroadcast(pk);

        // Mappings map = new Mappings(1e20, me);
        // BalancesStorage bs = new BalancesStorage(me);
        BalancesStorage bs = BalancesStorage(0x39f22FC216Eb3083ECF89C3b38cF4EB8B19b43aF);
        SemaphoreToken st = new SemaphoreToken(5e15, 1e20, 0x39f22FC216Eb3083ECF89C3b38cF4EB8B19b43aF);
        bs.increaseBalance(address(st), 1e20);
        bs.transferOwnership(address(st));

        console.log(address(bs));
        console.log(payable(address(st)));

        vm.stopBroadcast();
    }
}
