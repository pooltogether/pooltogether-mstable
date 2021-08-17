import debug from 'debug';

import { JsonRpcProvider } from '@ethersproject/providers';
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
} from '@mstable/protocol';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { MassetMachine, StandardAccounts } from '@utils/machines';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers, waffle } from 'hardhat';

import { MStableYieldSourceHarness } from '../types/pooltogether';

const { AddressZero, MaxUint256 } = ethers.constants;

const toWei = ethers.utils.parseEther;

describe('MStableYieldSource', () => {
    let yieldSourceManager: SignerWithAddress;
    let yieldSourceOwner: SignerWithAddress;
    let wallet2: SignerWithAddress;

    let erc20Token: MockERC20;
    let mAssetMachine: MassetMachine;
    let mStableYieldSource: MStableYieldSourceHarness;
    let mUSD: MockMasset;
    let nexus: MockNexus;
    let sa: StandardAccounts;
    let savings: SavingsContract;
    let savingsFactory: SavingsContract__factory;

    let isConstructorTest = false;

    const initializeMStableYieldSource = async (savingsAddress: string) => {
        const mStableYieldSourceFactory = await ethers.getContractFactory('MStableYieldSourceHarness');
        const hardhatMStableYieldSource = await mStableYieldSourceFactory.deploy(savingsAddress);

        return (mStableYieldSource = (await ethers.getContractAt(
            'MStableYieldSourceHarness',
            hardhatMStableYieldSource.address,
            yieldSourceOwner,
        )) as unknown as MStableYieldSourceHarness);
    };

    const createNewSavingsContract = async (): Promise<void> => {
        savingsFactory = new SavingsContract__factory(sa.default.signer);

        const impl = await savingsFactory.deploy(nexus.address, mUSD.address);
        const data = impl.interface.encodeFunctionData('initialize', [sa.default.address, 'Interest bearing mUSD', 'imUSD']);
        const proxy = await new AssetProxy__factory(sa.default.signer).deploy(impl.address, sa.dummy4.address, data);

        savings = savingsFactory.attach(proxy.address);

        const mockSavingsManager = await new MockSavingsManager__factory(sa.default.signer).deploy(savings.address);
        await nexus.setSavingsManager(mockSavingsManager.address);
    };

    beforeEach(async () => {
        const accounts = await ethers.getSigners();
        [yieldSourceOwner, yieldSourceManager, wallet2] = accounts;

        debug('Deploying MStableYieldSource instance...');

        mAssetMachine = await new MassetMachine().initAccounts(accounts);

        sa = mAssetMachine.sa;
        nexus = await new MockNexus__factory(sa.default.signer).deploy(sa.governor.address, sa.governor.address, sa.dummy1.address);

        mUSD = await new MockMasset__factory(sa.default.signer).deploy(
            'mStable USD',
            'mUSD',
            18,
            yieldSourceOwner.address,
            toWei('100000000'),
        );

        erc20Token = await new MockERC20__factory(sa.default.signer).deploy(
            'Mock1',
            'MK1',
            18,
            yieldSourceOwner.address,
            toWei('100000000'),
        );

        await createNewSavingsContract();

        if (!isConstructorTest) {
            mStableYieldSource = await initializeMStableYieldSource(savings.address);
        }
    });

    describe('constructor()', () => {
        before(() => {
            isConstructorTest = true;
        });

        after(() => {
            isConstructorTest = false;
        });

        it('should initialize MStableYieldSource', async () => {
            const mStableYieldSource = await initializeMStableYieldSource(savings.address);

            expect(await mStableYieldSource.owner()).to.equal(yieldSourceOwner.address);
            expect(await mStableYieldSource.savings()).to.equal(savings.address);
            expect(await mStableYieldSource.mAsset()).to.equal(mUSD.address);
        });

        it('should fail if savings is address zero', async () => {
            await expect(initializeMStableYieldSource(AddressZero)).to.be.revertedWith('MStableYieldSource/savings-not-zero-address');
        });
    });

    describe('assetManager()', () => {
        it('should setAssetManager', async () => {
            await expect(mStableYieldSource.connect(yieldSourceOwner).setAssetManager(yieldSourceManager.address))
                .to.emit(mStableYieldSource, 'AssetManagerTransferred')
                .withArgs(ethers.constants.AddressZero, yieldSourceManager.address);

            expect(await mStableYieldSource.assetManager()).to.equal(yieldSourceManager.address);
        });

        it('should fail to setAssetManager', async () => {
            await expect(mStableYieldSource.connect(yieldSourceOwner).setAssetManager(ethers.constants.AddressZero)).to.be.revertedWith(
                'onlyOwnerOrAssetManager/assetManager-not-zero-address',
            );
        });
    });

    describe('approveMaxAmount()', () => {
        it('should approve mStable savings to spend max uint256 amount of mUSD', async () => {
            await mStableYieldSource.decreaseAllowance(mUSD.address, savings.address, MaxUint256);

            await mStableYieldSource.approveMaxAmount();

            expect(await mUSD.allowance(mStableYieldSource.address, savings.address)).to.equal(MaxUint256);
            expect(await mStableYieldSource.callStatic.approveMaxAmount()).to.equal(true);
        });

        it('should fail if not owner', async () => {
            await expect(mStableYieldSource.connect(wallet2).callStatic.approveMaxAmount()).to.be.revertedWith(
                'Ownable: caller is not the owner',
            );
        });
    });

    describe('depositToken()', () => {
        it('should return mAsset token address', async () => {
            expect(await mStableYieldSource.depositToken()).to.equal(mUSD.address);
        });
    });

    describe('balanceOfToken()', () => {
        it('should return user balance', async () => {
            const yieldSourceOwnerBalance = toWei('100');
            const wallet2Balance = toWei('100');

            await mUSD.connect(yieldSourceOwner).approve(mStableYieldSource.address, yieldSourceOwnerBalance);
            await mStableYieldSource.connect(yieldSourceOwner).supplyTokenTo(yieldSourceOwnerBalance, yieldSourceOwner.address);

            await mUSD.connect(yieldSourceOwner).transfer(wallet2.address, wallet2Balance);

            await mUSD.connect(wallet2).approve(mStableYieldSource.address, wallet2Balance);
            await mStableYieldSource.connect(wallet2).supplyTokenTo(wallet2Balance, wallet2.address);

            expect(await mStableYieldSource.balanceOfToken(yieldSourceOwner.address)).to.equal(yieldSourceOwnerBalance);
            expect(await mStableYieldSource.balanceOfToken(wallet2.address)).to.equal(wallet2Balance);
        });
    });

    describe('supplyTokenTo()', () => {
        let yieldSourceOwnerBalance: BigNumber;

        beforeEach(() => {
            yieldSourceOwnerBalance = toWei('300');
        });

        it('should supply mAssets', async () => {
            await mUSD.connect(yieldSourceOwner).approve(mStableYieldSource.address, yieldSourceOwnerBalance);

            expect(await mStableYieldSource.connect(yieldSourceOwner).supplyTokenTo(yieldSourceOwnerBalance, yieldSourceOwner.address))
                .to.emit(mStableYieldSource, 'Supplied')
                .withArgs(yieldSourceOwner.address, yieldSourceOwner.address, yieldSourceOwnerBalance);

            expect(await mStableYieldSource.balanceOfToken(yieldSourceOwner.address)).to.equal(yieldSourceOwnerBalance);
        });

        it('should revert if balance is not superior to 0', async () => {
            await expect(
                mStableYieldSource.connect(yieldSourceOwner).supplyTokenTo(toWei('0'), yieldSourceOwner.address),
            ).to.be.revertedWith('Must deposit something');
        });
    });

    describe('redeemToken()', () => {
        let yieldSourceOwnerBalance: BigNumber;
        let redeemAmount: BigNumber;

        beforeEach(() => {
            yieldSourceOwnerBalance = toWei('300');
            redeemAmount = toWei('100');
        });

        it('should redeem assets', async () => {
            await mUSD.connect(yieldSourceOwner).approve(mStableYieldSource.address, yieldSourceOwnerBalance);
            await mStableYieldSource.connect(yieldSourceOwner).supplyTokenTo(yieldSourceOwnerBalance, yieldSourceOwner.address);

            expect(await mStableYieldSource.connect(yieldSourceOwner).redeemToken(redeemAmount))
                .to.emit(mStableYieldSource, 'Redeemed')
                .withArgs(yieldSourceOwner.address, redeemAmount, redeemAmount);

            expect(await mStableYieldSource.balanceOfToken(yieldSourceOwner.address)).to.equal(yieldSourceOwnerBalance.sub(redeemAmount));
        });

        it('should not be able to redeem assets if balance is 0', async () => {
            await expect(mStableYieldSource.connect(yieldSourceOwner).redeemToken(redeemAmount)).to.be.revertedWith(
                'ERC20: burn amount exceeds balance',
            );
        });

        it('should fail to redeem if amount superior to balance', async () => {
            const yieldSourceOwnerLowBalance = toWei('10');

            await mUSD.connect(yieldSourceOwner).approve(mStableYieldSource.address, yieldSourceOwnerLowBalance);
            await mStableYieldSource.connect(yieldSourceOwner).supplyTokenTo(yieldSourceOwnerLowBalance, yieldSourceOwner.address);

            await expect(mStableYieldSource.connect(yieldSourceOwner).redeemToken(redeemAmount)).to.be.revertedWith(
                'ERC20: burn amount exceeds balance',
            );
        });
    });

    describe('transferERC20()', () => {
        let transferAmount: BigNumber;

        beforeEach(async () => {
            transferAmount = toWei('10');

            await erc20Token.connect(yieldSourceOwner).transfer(mStableYieldSource.address, transferAmount);
        });

        it('should transferERC20 if yieldSourceOwner', async () => {
            expect(await mStableYieldSource.connect(yieldSourceOwner).transferERC20(erc20Token.address, wallet2.address, transferAmount))
                .to.emit(mStableYieldSource, 'TransferredERC20')
                .withArgs(yieldSourceOwner.address, wallet2.address, transferAmount, erc20Token.address);
        });

        it('should transferERC20 if assetManager', async () => {
            await mStableYieldSource.connect(yieldSourceOwner).setAssetManager(yieldSourceManager.address);

            expect(
                await mStableYieldSource
                    .connect(yieldSourceManager)
                    .transferERC20(erc20Token.address, yieldSourceOwner.address, transferAmount),
            )
                .to.emit(mStableYieldSource, 'TransferredERC20')
                .withArgs(yieldSourceManager.address, yieldSourceOwner.address, transferAmount, erc20Token.address);
        });

        it('should not allow to transfer imAsset tokens', async () => {
            await expect(
                mStableYieldSource.connect(yieldSourceOwner).transferERC20(savings.address, wallet2.address, transferAmount),
            ).to.be.revertedWith('MStableYieldSource/imAsset-transfer-not-allowed');
        });

        it('should fail to transferERC20 if not yieldSourceOwner or assetManager', async () => {
            await expect(
                mStableYieldSource.connect(wallet2).transferERC20(erc20Token.address, yieldSourceOwner.address, transferAmount),
            ).to.be.revertedWith('onlyOwnerOrAssetManager/owner-or-manager');
        });
    });
});
