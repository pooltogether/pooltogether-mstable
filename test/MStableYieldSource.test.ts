import debug from "debug";

import { JsonRpcProvider } from "@ethersproject/providers";
import {
    AssetProxy__factory,
    MockERC20,
    MockERC20__factory,
    MockMasset,
    MockMasset__factory,
    MockNexus,
    MockNexus__factory,
    MockSavingsManager__factory,
    SavingsContract,
    SavingsContract__factory,
} from "@mstable/protocol";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MassetMachine, StandardAccounts } from "@utils/machines";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";

import { MStableYieldSource } from "../types/pooltogether";

const toWei = ethers.utils.parseEther;

describe("MStableYieldSource", () => {
    let contractsOwner: SignerWithAddress;
    let yieldSourceOwner: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let provider: JsonRpcProvider;

    let bAsset: MockERC20;
    let bAsset2: MockERC20;
    let bAssets: MockERC20[];
    let mAssetMachine: MassetMachine;
    let mStableYieldSource: MStableYieldSource;
    let mUSD: MockMasset;
    let nexus: MockNexus;
    let sa: StandardAccounts;
    let savingsContract: SavingsContract;
    let savingsFactory: SavingsContract__factory;

    const createNewSavingsContract = async (): Promise<void> => {
        savingsFactory = new SavingsContract__factory(sa.default.signer);

        const impl = await savingsFactory.deploy(nexus.address, mUSD.address);
        const data = impl.interface.encodeFunctionData("initialize", [sa.default.address, "Savings Credit", "imUSD"]);
        const proxy = await new AssetProxy__factory(sa.default.signer).deploy(impl.address, sa.dummy4.address, data);

        savingsContract = savingsFactory.attach(proxy.address);

        const mockSavingsManager = await new MockSavingsManager__factory(sa.default.signer).deploy(savingsContract.address);
        await nexus.setSavingsManager(mockSavingsManager.address);
    };

    beforeEach(async () => {
        const accounts = await ethers.getSigners();
        [contractsOwner, yieldSourceOwner, wallet2] = accounts;

        provider = waffle.provider;

        debug("Deploying MStableYieldSource instance...");

        mAssetMachine = await new MassetMachine().initAccounts(accounts);

        sa = mAssetMachine.sa;
        nexus = await new MockNexus__factory(sa.default.signer).deploy(sa.governor.address, sa.governor.address, sa.dummy1.address);

        mUSD = await new MockMasset__factory(sa.default.signer).deploy(
            "mStable USD",
            "mUSD",
            18,
            sa.fundManager.address,
            toWei("100000000"),
        );
        bAsset = await new MockERC20__factory(sa.default.signer).deploy("Mock1", "MK1", 18, sa.fundManager.address, toWei("100000000"));
        bAsset2 = await new MockERC20__factory(sa.default.signer).deploy("Mock2", "MK2", 18, sa.fundManager.address, toWei("100000000"));

        bAssets = [bAsset, bAsset2];

        createNewSavingsContract();

        const mStableYieldSourceFactory = await ethers.getContractFactory("MStableYieldSource");
        const hardhatMStableYieldSource = await mStableYieldSourceFactory.deploy(savingsContract.address);

        mStableYieldSource = (await ethers.getContractAt(
            "MStableYieldSource",
            hardhatMStableYieldSource.address,
            contractsOwner,
        )) as unknown as MStableYieldSource;
    });
});
