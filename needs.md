Securitybase.sol

function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyValidRole(accessControl.EMERGENCY_ROLE()) {
        // Implementation depends on specific contract needs, implement this
        
        emit SecurityViolation(msg.sender, "Emergency withdrawal triggered");
    }


in Secureborrowoperions 

 if (isDebtIncrease && usdfChange > 0) {
            usdfToken.mint(msg.sender, usdfChange);
            if (borrowingFee > 0) {
                // usdfToken.mint(accessControl.getFeeRecipient(), borrowingFee); here accesscontrol.getfeerecipent is not a function
            }
        } else if (!isDebtIncrease && usdfChange > 0) {
            usdfToken.burnFrom(msg.sender, usdfChange);
        }