// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";


// Балансы и по сути сам токен тут только тссс...))
// Отдельный контракт, чтобы можно было обновлять контракт, но сохранять балансы
contract Mappings is IERC20 {
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    address public owner; // = Actual SemaphoreToken contract
    uint256 private totalSupply_;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        totalSupply_ = initialSupply;
        balances[owner] = initialSupply;
    }

    function changeOwner(address newOwner) public onlyOwner {
        transfer(newOwner, balanceOf(owner));
        owner = newOwner;
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
        return balances[account];
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
        return allowances[_owner][spender];
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, allowances[sender][msg.sender] - amount);
        return true;
    }

    function privilegedTransfer(address from, address to, uint256 amount) public onlyOwner {
        _transfer(from, to, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(balances[sender] >= amount, "ERC20: transfer amount exceeds balance");

        balances[sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        totalSupply_ += amount;
        balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        require(balances[account] >= amount, "ERC20: burn amount exceeds balance");

        balances[account] -= amount;
        totalSupply_ -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address _owner, address spender, uint256 amount) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        allowances[_owner][spender] = amount;
        emit Approval(_owner, spender, amount);
    }
}

// Правила обмена эфира на токены и наоборот + управление балансами происходит черег этот контракт
contract SemaphoreToken {
    // Дополнительные события
    event Received(address indexed sender, uint256 amount);
    event TokensPurchased(address indexed purchaser, uint256 amount);
    event TokensExchanged(address indexed exchanger, uint256 ethAmount);

    address public owner;
    uint256 public exchangeRate; // Количество wei за 1 SemaphoreToken

    Mappings balances;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor(uint256 _exchangeRate, address mappingsAddress) {
        owner = msg.sender;
        exchangeRate = _exchangeRate;
        balances = Mappings(mappingsAddress);
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances.balanceOf(account);
    }

    function privilegedTransfer(address from, address to, uint256 amount) public onlyOwner {
        balances.privilegedTransfer(from, to, amount);
    }

    receive() external payable {
        uint256 tokenAmount = msg.value / exchangeRate;
        balances.privilegedTransfer(owner, msg.sender, tokenAmount);

        emit Received(msg.sender, msg.value);
        emit TokensPurchased(msg.sender, tokenAmount);
    }

    function setExchangeRate(uint256 newRate) public onlyOwner {
        exchangeRate = newRate;
    }

    function exchangeTokens(uint256 tokenAmount, address payable recipient) public {
        require(balances.balanceOf(msg.sender) >= tokenAmount, "Insufficient tokens to exchange");
        uint256 etherAmount = tokenAmount * exchangeRate;
        require(address(this).balance >= etherAmount, "Contract has insufficient Ether");

        balances.privilegedTransfer(msg.sender, owner, tokenAmount);
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

        Mappings map = new Mappings(1e20);
        // SemaphoreToken st = new SemaphoreToken(5e15, address(map));

        console.log(address(map));
        // console.log(address(st));

        vm.stopBroadcast();
    }
}
