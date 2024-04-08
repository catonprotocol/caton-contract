import "@stdlib/deploy";

// todo
// 权限问题
// 可以重新设置keyInfoMap

// message PurchaseOnekey {
//     keyNum: Int as uint8;  // keyItem的序号
// }

message Purchasekeys {
    keyNum: Int as uint8;  // keyItem的序号
    quantity: Int as uint8;  // 购买多少个
}

message RedeemKeys {
    length: Int as uint128;
    keyIdMap: map<Int, Int>;
}

message Redeem {
    keyId: Int as uint128;
}


message PeriodStartSwith {
    swithFlag: Bool;
}

message OpenLucker {
    period: Int as uint128;
    calcUserRewardFlag: Bool;
}

message SetKeyRewardContractAddress {
    keyRewardContractAddress: Address;
}

message Withdraw {
    amount: Int as coins;
}

message UpdateFeeRate {
    purchaseFeeRate: Int as uint256;
    redeemFeeRate: Int as uint256;
}

message SetVaultAddress {
    vaultAddress: Address;
}

message ReSetKeyInfo {
    length: Int as uint256;
    keyInfoMap: map<Int, KeyInfo>;
}

message ClearKeyInfo {
    length: Int as uint256;
    keyIdMap: map<Int, Int>;
}


struct KeyInfo {
    owner: Address;
    keyNum: Int as uint8;
    price: Int as uint256;
}



struct KeyCollectInfo {
    keySupply: Int as uint256;
    keyShares: Int as uint256;
    totalVluck: Int as uint256;
    rewardPreVluck: Int as uint256;
    totalRewardVluck: Int as uint256;    // 总奖励
    luckNum: Int as uint8;
    period: Int as uint128;
    keyRewardContractAddress: Address;
    vaultAddress: Address;
    totalValutValue: Int as uint256;
    valutValue: Int as uint256;        // total fee
}

struct PeriodInfo {
    // startTime: Int as uint32;
    // endTime: Int as uint32;
    // status: Int as uint8;
    luckNum: Int as uint8;
    totalReward: Int as uint256;
    rewardPreVluck: Int as uint256; 
    totalVluck: Int as uint256;
}




contract KeyCollection with Deployable {

    const minTonsForStorage: Int = ton("0.03");
    const gasConsumption: Int = ton("0.03");

    purchaseFeeRate: Int as uint256 = 25000000; // 0.025 * 1000000000
    redeemFeeRate: Int as uint256 = 25000000;
    winFeeRate: Int as uint256 = 50000000;

    owner: Address;
    vaultAddress: Address;  //default contract owner
    totalValutValue: Int as uint256 = 0;
    valutValue: Int as uint256 = 0;

    totalVluck: Int as uint256 = 0;    // 总投入ton值
    vluckMap: map<Int, Int>;            // 记录每个格子(一共8个格子)的vluck值

    keySupply: Int as uint256 = 0; // 所有key的发行量
    keyShares: Int as uint256 = 0; // 所有key的在持份额
    keySharesMap: map<Int, Int>;    // 每个格子key的份额数量

    // 计算每一份vlcok的奖励
    rewardPreVluck: Int as uint256 = 0;
    userVluckMap: map<Address, Int>;      // 记录用户的vluck值
    userAwardMap: map<Address, Int>;     // 用户奖励
    keyInfoMap: map<Int, KeyInfo>;  // 记录每个key的具体信息
    // keysOwnerMap: map<Int, Address>; // 记录每个key的拥有者
    luckNum: Int as uint8 = 0;
    // userWalletMap: map<Address, Int>;

    period: Int as uint128 = 1;
    periodInfoMap: map<Int, PeriodInfo>;  // 每期的中奖情况
    periodStartSwitch: Bool = true;

    keyRewardContractAddress: Address;
    totalCalcReward: Int as uint256 = 0;

    init(owner: Address) {
		self.owner = owner;
        self.vaultAddress = owner; 
        self.keyRewardContractAddress = newAddress(0, 0);
        let i: Int = 0;
        repeat (8) {
            i = i + 1;
            self.keySharesMap.set(i, 0);
            self.vluckMap.set(i, 0);
        }
    }

    fun calcPrice(shares: Int): Int {
        if(shares<=0){
            return 0;
        }
        let tmp: Int = shares * shares;
        tmp = tmp * 1000000;
        return tmp;
    }

    fun getVluckByAddr(user: Address): Int {
        let vLuck: Int = 0;

        if (self.userVluckMap.get(user) != null) {
            vLuck = self.userVluckMap.get(user)!!;
        }
        return vLuck;
    }

    fun updateKeySharesMap(keyNum: Int, count: Int) {     // +1 or -1
        let subKeyNum: Int = self.keySharesMap.get(keyNum)!!;
        subKeyNum = subKeyNum + count;
        self.keySharesMap.set(keyNum, subKeyNum);   // 设置对应key的发行量
    }

    fun updateVluckMap(keyNum: Int, vluck: Int) {
        let totalVluck: Int = self.vluckMap.get(keyNum)!!;
        totalVluck = totalVluck + vluck;
        self.vluckMap.set(keyNum, totalVluck);
    }

    fun updateUserVluckMap(user: Address, vluck: Int) {

        let totalVluck: Int = vluck;
        if (self.userVluckMap.get(user) != null) {
            let userVluck: Int = self.userVluckMap.get(user)!!;
            totalVluck = totalVluck + userVluck;
        }
        self.userVluckMap.set(user, totalVluck);

    }

    // fun updateUserAwardMap(user: Address, reward: Int) {
    //     let totalReward: Int = reward;
    //     if (self.userAwardMap.get(user) != null) {
    //         let haveReward: Int = self.userAwardMap.get(user)!!;
    //         totalReward = totalReward + haveReward;
    //     }
    //     self.userAwardMap.set(user, totalReward);
    //     // self.userAwardMap.set(user, reward);
    // }

    fun msgValue(msgValue: Int): Int {
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        msgValue = msgValue - (storageFee + self.gasConsumption);
        return msgValue;
    }

    receive() {}

    receive(msg: SetVaultAddress) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can set the vault address");
        self.vaultAddress = msg.vaultAddress;
    }

    receive(msg: UpdateFeeRate) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can set the fee rate");
        self.purchaseFeeRate = msg.purchaseFeeRate;
        self.redeemFeeRate = msg.redeemFeeRate;
    }

    receive(msg: PeriodStartSwith) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can set period start swith");
        self.periodStartSwitch = msg.swithFlag;
    }

    receive(msg: SetKeyRewardContractAddress) {
         let ctx: Context = context();
        require(ctx.sender == self.owner, "Only owner can set reward address");
        self.keyRewardContractAddress = msg.keyRewardContractAddress;
    }

    receive(msg: Purchasekeys) {
        let ctx: Context = context();
        require(self.periodStartSwitch == true, "new period is not start");
        require(msg.quantity <= 100, "The quantity should be less than 100");
        let subKeyNum: Int = self.keySharesMap.get(msg.keyNum)!!; // 获取当前格子的数量
        // self.updateKeySharesMap(msg.keyNum, msg.quantity);
        let totalPrice: Int = 0;
        repeat(msg.quantity) {
            subKeyNum = subKeyNum + 1;
            self.keySupply = self.keySupply + 1;
            self.keyShares = self.keyShares + 1;
            let price: Int = self.calcPrice(subKeyNum);
            self.keyInfoMap.set(self.keySupply, KeyInfo{owner: sender(), keyNum:msg.keyNum, price: price});
            totalPrice = totalPrice + price;
            
        }
        let value: Int = self.msgValue(context().value);
        // let purchaseFee: Int = totalPrice * self.purchaseFeeRate / 1000000000;
        let purchaseFee: Int = totalPrice * self.purchaseFeeRate / ton("1");  // purchase fee rate 2.5%
        self.valutValue = self.valutValue + purchaseFee;
        self.totalValutValue = self.totalValutValue + purchaseFee;
        value = value - purchaseFee;
        // dump(totalPrice);
        // dump(value);
        require(value >= totalPrice, "Invalid value!!");
        let refundAmount: Int = value - totalPrice; // 需要退款的钱
        self.totalVluck = self.totalVluck + totalPrice;       // 计算总的vluck
        self.updateUserVluckMap(ctx.sender, totalPrice);
        self.updateVluckMap(msg.keyNum, totalPrice);
        self.updateKeySharesMap(msg.keyNum, msg.quantity);
        // dump(refundAmount);
        send(SendParameters{
            to: ctx.sender,
            value: refundAmount,
            // mode: SendIgnoreErrors,
            body: "Successfully purchase keys".asComment()
        });

        if (self.valutValue >= ton("1")){
            send(SendParameters{
                to: self.vaultAddress,
                value: self.valutValue,
                mode: SendPayGasSeparately,
                body: "Successfully send valut".asComment()
            });
            self.valutValue = 0;
        }

    }


    receive(msg: RedeemKeys) {
        let ctx: Context = context();
        require(self.periodStartSwitch == true, "new period is not start");
        require(msg.length <= 100, "The length should be less than 100");
        let i: Int = 0;
        let totalOrgAmount: Int = 0;
        let totalRedeemAmount: Int = 0;
        repeat(msg.length) {
            i = i + 1;
            let keyId: Int = msg.keyIdMap.get(i)!!;
            let keyInfo: KeyInfo = self.keyInfoMap.get(keyId)!!;
            require(ctx.sender == keyInfo.owner, "Only owner can redeem");
            totalOrgAmount = totalOrgAmount + keyInfo.price;
            let subKeyNum: Int = self.keySharesMap.get(keyInfo.keyNum)!!; // 获取当前格子的数量
            let cPrice: Int = self.calcPrice(subKeyNum - 1);  // 计算当前的价格
            totalRedeemAmount = totalRedeemAmount + cPrice;

            self.keyShares = self.keyShares - 1;
            self.updateKeySharesMap(keyInfo.keyNum, -1);
            self.keyInfoMap.set(keyId, null);
        }
        self.totalVluck = self.totalVluck - totalOrgAmount;
        // let refundAmount: Int = self.msgValue(ctx.value);
        // totalRedeemAmount = totalRedeemAmount + refundAmount;

        // let redeemFee: Int = totalRedeemAmount * self.redeemFeeRate / 1000000000;
        let redeemFee: Int = totalRedeemAmount * self.redeemFeeRate / ton("1");
        // dump(redeemFee);
        self.valutValue = self.valutValue + redeemFee;
        // dump(self.valutValue);
        self.totalValutValue = self.totalValutValue + redeemFee;
        totalRedeemAmount = totalRedeemAmount - redeemFee;
        let value: Int = self.msgValue(ctx.value);
        let refundAmount: Int = totalRedeemAmount + value;

        if(totalRedeemAmount > 0) {
            send(SendParameters{
                to: ctx.sender,
                value: refundAmount,
                // mode: SendPayGasSeparately + SendIgnoreErrors,
                body: "Successfully redeem keys".asComment()
            });
        }
        self.updateUserVluckMap(ctx.sender, -totalOrgAmount);

        if (self.valutValue >= ton("1")){
            send(SendParameters{
                to: self.vaultAddress,
                value: self.valutValue,
                mode: SendPayGasSeparately,
                body: "Successfully send valut".asComment()
            });
            self.valutValue = 0;
        }
    }

    // receive(msg: ReSetKeyInfo) {

    // }

    receive(msg: ClearKeyInfo) {
        let ctx: Context = context();
        require(self.owner == ctx.sender, "only owner can clean key info");
        let i: Int = 0;
        repeat(msg.length) {
            i = i + 1;
            let keyId: Int = msg.keyIdMap.get(i)!!;
            self.keyInfoMap.set(keyId, null);
        }
        // dump("ClearKeyInfo over ...");
    }


    receive(msg: OpenLucker) {
        let ctx: Context = context();
        require(self.owner == ctx.sender, "only owner can open lucker");
        require(msg.period == self.period, "period is wrong");
        self.periodStartSwitch = false;
        let luckNum: Int = random(1,8);
        self.luckNum = luckNum;

        // burn all keyItem(num==luckNum)
        let vluck: Int = self.vluckMap.get(luckNum)!!;
        self.totalVluck = self.totalVluck - vluck;      // 开奖后剩余的vluck值
        self.vluckMap.set(luckNum, 0);                  // 清空对应的第几个格子的vluck值

        let winFee: Int = vluck * self.winFeeRate;
        winFee = winFee/ton("1");
        let rewardVluck: Int = vluck - winFee;

        // self.rewardPreVluck = rewardVluck * 1000000000;
        self.rewardPreVluck = rewardVluck * ton("1");
        self.rewardPreVluck = self.rewardPreVluck / self.totalVluck;
        // dump(self.rewardPreVluck);
        self.periodInfoMap.set(self.period, PeriodInfo{
            luckNum: luckNum,
            rewardPreVluck: self.rewardPreVluck,
            totalReward: rewardVluck,
            totalVluck: self.totalVluck
        });
        // todo 发送奖励到派奖合约
        // let forwardFee: Int = ctx.readForwardFee();
        // dump(rewardVluck);
        send(SendParameters{
            to: self.keyRewardContractAddress,
            value: rewardVluck,
            mode: SendPayGasSeparately,
            bounce: true
            // body: "Successfully send reward".asComment()
        });
        // dump(self.keySupply);
        // if (msg.calcUserRewardFlag) {
        //     // todo发送交易去RecordReward合约
        //     let i: Int = 0;
        //     self.totalCalcReward = 0;
        //     self.userAwardMap = emptyMap();
        //     repeat(self.keySupply) {
        //         i = i + 1;
        //         dump(i);
        //         if (self.keyInfoMap.get(i) !=null ){
        //             let keyInfo: KeyInfo = self.keyInfoMap.get(i)!!;
        //             if (keyInfo.keyNum == self.luckNum) {
        //                 self.keyInfoMap.set(i, null);
        //             } else {
        //                 let reward: Int = self.rewardPreVluck * keyInfo.price;
        //                 reward = reward / ton("1");
        //                 self.updateUserAwardMap(keyInfo.owner, reward);
        //                 self.totalCalcReward = self.totalCalcReward + reward;
        //             }
        //         }
        //     }
        //     self.periodStartSwitch = true;
        // }
        self.period = self.period + 1;
    }


    // this will withdraw a specific amount but leave 0.01 for storage rent costs
    receive(msg: Withdraw) {
        let ctx: Context = context();
        require(self.owner == ctx.sender, "only owner can withdraw");
        let amount: Int = min(msg.amount, myBalance() - context().value - self.minTonsForStorage);
        require(amount > 0, "Insufficient balance");
        send(SendParameters{
            to: sender(),
            bounce: true,
            value: amount,
            mode: SendRemainingValue + SendIgnoreErrors
        });
    }

    receive("withdraw all") {
        let ctx: Context = context();
        require(self.owner == ctx.sender, "only owner can withdraw");
        send(SendParameters{
            to: sender(),
            bounce: true,
            value: 0,
            mode: SendRemainingBalance + SendIgnoreErrors
        });
    }

    // get fun currentPrice(): Int {
    //     let shares: Int = self.keyShares + 1;
    //     return self.calcPrice(shares);
    // }


    get fun userVluck(user: Address): Int {
        return self.getVluckByAddr(user);
    }

    get fun vluckByNum(num: Int): Int {
        return self.vluckMap.get(num)!!;
    }

    get fun userAwardMap(): map<Address, Int> {
        return self.userAwardMap;
    }

    get fun keyCollectInfo(): KeyCollectInfo {
        return KeyCollectInfo{
            keySupply: self.keySupply,
            keyShares: self.keyShares,
            totalVluck: self.totalVluck,
            rewardPreVluck: self.rewardPreVluck,
            totalRewardVluck: 0,
            luckNum: self.luckNum,
            period: self.period,
            keyRewardContractAddress: self.keyRewardContractAddress,
            vaultAddress: self.vaultAddress,
            totalValutValue: self.totalValutValue,
            valutValue: self.valutValue
        };
    }

    get fun allKeyInfo(): map<Int, KeyInfo> {
        return self.keyInfoMap;
    }

    get fun keyInfoByPage(start: Int, limit: Int): map<Int, KeyInfo> {
        let keyInfoMapTemp: map<Int, KeyInfo> = emptyMap();
        let i: Int = start;
        repeat(limit) {
            i = i + 1;
            if (self.keyInfoMap.get(i) !=null ){
                let keyInfo: KeyInfo = self.keyInfoMap.get(i)!!;
                keyInfoMapTemp.set(i, keyInfo);
            }
        }
        return keyInfoMapTemp;
    }

    get fun keyInfo(user: Address): map<Int, KeyInfo> {
        let userKeyInfoMap: map<Int, KeyInfo> = emptyMap();
        let i: Int = 0;
        repeat(self.keySupply) {
            i = i + 1;
            if (self.keyInfoMap.get(i) !=null ){
                let keyInfo: KeyInfo = self.keyInfoMap.get(i)!!;
                if(keyInfo.owner == user) {
                    userKeyInfoMap.set(i, keyInfo);
                }

            }
        }
        return userKeyInfoMap;
    }

    get fun keyInfoByNum(keyNum: Int): map<Int, KeyInfo> {
        let keyInfoMap: map<Int, KeyInfo> = emptyMap();
        let i: Int = 0;

        repeat(self.keySupply) {
            i = i + 1;
            if (self.keyInfoMap.get(i) !=null ){
                let keyInfo: KeyInfo = self.keyInfoMap.get(i)!!;
                if(keyInfo.keyNum == keyNum) {
                    keyInfoMap.set(i, keyInfo);
                }

            }
        }
        return keyInfoMap;
    }

    get fun keyInfoById(id: Int): KeyInfo? {
        return self.keyInfoMap.get(id);
    }

    get fun balance(): Int {
        return myBalance();
    }

    get fun totalCalcReward(): Int {
        return self.totalCalcReward;
    }

    get fun userVluckMap(): map<Address, Int> {
        return self.userVluckMap;
    }

    get fun vluckMap(): map<Int, Int> {
        return self.vluckMap;
    }

    get fun vluckByKeyNum(keyNum: Int):Int {
        return self.vluckMap.get(keyNum)!!;
    }

    get fun allKeySharesMap(): map<Int, Int> {
        return self.keySharesMap;
    }

    get fun keySharesMap(keyNum: Int): Int{
        return self.keySharesMap.get(keyNum)!!;
    }

    get fun periodInfo(period: Int): PeriodInfo {
        return self.periodInfoMap.get(period)!!;
    }


}