// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 
// Your token contract
contract Token is Ownable, ERC20 {
    string private constant _symbol = 'MIR';                 // TODO: Give your token a symbol (all caps!)
    string private constant _name = 'Sofilian';                   // TODO: Give your token a name
    bool private mint_active =true;
    constructor() ERC20(_name, _symbol) {}

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================

    // Function _mint: Create more of your tokens.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function mint(uint amount) 
        public 
        onlyOwner
    {
        /******* TODO: Implement this function *******/
        require(mint_active, "Minting is disabled");
        require(amount>0, "Amount mas be greater then 0");
        _mint(msg.sender, amount);
    }

    // Function _disable_mint: Disable future minting of your token.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function disable_mint()
        public
        onlyOwner
    {
        /******* TODO: Implement this function *******/
         mint_active = false;

    }
}