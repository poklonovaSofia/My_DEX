// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
//import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = '';

    address tokenAddr= 0x5FbDB2315678afecb367f032d93F642f64180aa3;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);

//constructor for testing file
//    constructor(address _tokenAddr) {
//        tokenAddr = _tokenAddr;
//        token = Token(_tokenAddr);
//    }
    //basic constructor
    constructor() {}
    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    mapping(address => uint) private lps;
    uint private totalShares = 0;
    mapping(address => uint) private lpShares;
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;

    // liquidity rewards
    uint private swap_fee_numerator = 3;
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;
    function getTokenReserves() external view returns (uint) {
        return token_reserves;
    }

    function getEthReserves() external view returns (uint) {
        return eth_reserves;
    }
    function getCurrentRate()
        external
        view
        returns (uint)
    {
        uint current_exchange_rate = (token_reserves * 1e18) / eth_reserves;
        return current_exchange_rate;
    }

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================

    /* ========================= Liquidity Provider Functions =========================  */

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        /******* TODO: Implement this function *******/
        require(token_reserves>0 && eth_reserves>0, "Pool is not exist");
        require(msg.value>0, "ETH is not sent");
        uint current_exchange_rate = (token_reserves * 1e18) / eth_reserves;//Calculating the current exchange rate (tokens for 1 ETH)
        require(current_exchange_rate>=min_exchange_rate
            && current_exchange_rate<=max_exchange_rate,
            "Exchange rate out of bounds");

        uint requiredTokens = (msg.value*token_reserves)/eth_reserves;
        require(requiredTokens > 0, "Invalid token amount");
        require(token.balanceOf(msg.sender)>requiredTokens, "Sender has not enough tokens");
        require(token.transferFrom(msg.sender,address(this),requiredTokens),"Token transfer failed");
        uint shares;
        if (totalShares == 0) {
            shares = msg.value; // initial LP
        } else {
            shares = (msg.value * totalShares) / eth_reserves;
        }
        require(shares > 0, "Zero shares");
        lpShares[msg.sender] += shares;
        totalShares += shares;
        token_reserves+=requiredTokens;
        eth_reserves+=msg.value;

        k=token_reserves * eth_reserves;

        bool flag=false;
        for(uint i=0; i<lp_providers.length; i++) {
            if(lp_providers[i]==msg.sender) {
                flag=true;
                break;
            }
        }
        if(!flag){
            lp_providers.push(msg.sender);
        }
        lps[msg.sender] += msg.value;
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate) public payable {
        require(token_reserves > 0 && eth_reserves > 0, "Pool does not exist");
        require(amountETH > 0 && amountETH <= lps[msg.sender], "Invalid ETH amount");

        uint current_exchange_rate = (token_reserves * 1e18) / eth_reserves;
        require(current_exchange_rate >= min_exchange_rate && current_exchange_rate <= max_exchange_rate, "Exchange rate out of bounds");

        uint tokensToReturn = (amountETH * token_reserves) / eth_reserves;
        uint sharesToRemove = (amountETH * totalShares) / eth_reserves;

        require(eth_reserves >= amountETH, "ETH reserves too low");
        require(token_reserves >= tokensToReturn, "Token reserves too low");
        require(sharesToRemove <= lpShares[msg.sender], "Insufficient shares");

        // Оновлення стану перед відправкою
        lpShares[msg.sender] -= sharesToRemove;
        totalShares -= sharesToRemove;
        lps[msg.sender] -= amountETH;
        eth_reserves -= amountETH;
        token_reserves -= tokensToReturn;
        k = token_reserves * eth_reserves;

        // Переказ токенів
        require(token.transfer(msg.sender, tokensToReturn), "Token transfer failed");

        // Переказ ETH
        (bool sent, ) = msg.sender.call{value: amountETH}("");
        require(sent, "ETH transfer failed");

        if (lps[msg.sender] == 0) {
            for (uint i = 0; i < lp_providers.length; i++) {
                if (lp_providers[i] == msg.sender) {
                    removeLP(i);
                    break;
                }
            }
        }
    }
    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate) external payable {
        require(token_reserves > 0 && eth_reserves > 0, "Pool does not exist");
        require(lps[msg.sender] > 0, "No liquidity to remove");

        uint current_exchange_rate = (token_reserves * 1e18) / eth_reserves;
        require(current_exchange_rate >= min_exchange_rate && current_exchange_rate <= max_exchange_rate, "Exchange rate out of bounds");

        uint amountETH = lps[msg.sender];
        uint tokensToReturn = (amountETH * token_reserves) / eth_reserves;
        uint sharesToRemove = lpShares[msg.sender];

        require(eth_reserves >= amountETH, "ETH reserves too low");
        require(token_reserves >= tokensToReturn, "Token reserves too low");

        // Оновлення стану перед відправкою
        lpShares[msg.sender] = 0;
        totalShares -= sharesToRemove;
        lps[msg.sender] = 0;
        eth_reserves -= amountETH;
        token_reserves -= tokensToReturn;
        k = token_reserves * eth_reserves;

        // Переказ токенів
        require(token.transfer(msg.sender, tokensToReturn), "Token transfer failed");

        // Переказ ETH
        (bool sent, ) = msg.sender.call{value: amountETH}("");
        require(sent, "ETH transfer failed");

        for (uint i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] == msg.sender) {
                removeLP(i);
                break;
            }
        }
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.

    function swapTokensForETH(uint amountTokens, uint max_exchange_rate) external payable {
        require(amountTokens > 0 && token.balanceOf(msg.sender) >= amountTokens, "Invalid token amount");

        uint fee = (amountTokens * swap_fee_numerator) / swap_fee_denominator;
        uint effective_tokens = amountTokens - fee;

        uint new_token_reserve = token_reserves + effective_tokens;
        uint new_eth_reserve = k / new_token_reserve;
        uint eth_out = eth_reserves - new_eth_reserve;

        require(eth_out < eth_reserves - 1, "Must leave at least 1 wei ETH");
        require((eth_out * 1e18) / amountTokens <= max_exchange_rate, "Unacceptable rate");

        token.transferFrom(msg.sender, address(this), amountTokens);
        payable(msg.sender).transfer(eth_out);

        token_reserves += effective_tokens;
        eth_reserves -= eth_out;
        k = token_reserves * eth_reserves;
    }

    function swapETHForTokens(uint max_exchange_rate) external payable {
        require(msg.value > 0, "Must send ETH");

        uint eth_in = msg.value;
        uint fee = (eth_in * swap_fee_numerator) / swap_fee_denominator;
        uint effective_eth = eth_in - fee;

        uint new_eth_reserve = eth_reserves + effective_eth;
        uint new_token_reserve = k / new_eth_reserve;
        uint tokens_out = token_reserves - new_token_reserve;

        require(tokens_out < token_reserves - 1, "Must leave at least 1 token");
        require((tokens_out * 1e18) / eth_in <= max_exchange_rate, "Unacceptable rate");

        require(token.balanceOf(address(this)) >= tokens_out, "Not enough tokens in pool");

        eth_reserves += effective_eth;
        token_reserves -= tokens_out;
        k = token_reserves * eth_reserves;

        token.transfer(msg.sender, tokens_out);
    }
}
