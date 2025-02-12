import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/src/signers";
import {ethers} from "hardhat";
import {expect} from "chai";
import { ERC721Factory } from "../typechain-types";
import "@nomicfoundation/hardhat-chai-matchers";

const {abi: ERC721Abi} = require("../artifacts/contracts/factory/ERC721Factory.sol/ERC721Token.json");

let factory: ERC721Factory;
let owner: HardhatEthersSigner;
const royaltyFee = 50; // 0.5

const init = async() => {
    owner = (await ethers.getSigners())[0];
    const accounts = (await ethers.getSigners()).slice(1,);
    
    // nft
    const nftFactory = await ethers.getContractFactory("ERC721Factory");
    factory = await nftFactory.deploy();
    await factory.waitForDeployment();
}

describe("ERC721Factory test", function() {
    beforeEach(async function() {
        await init();
    });

    it ("Should be possible to create ERC721", async function() {
        const tokenName = "My Collection";
        const tokenSymbol = "MC";
        const baseUri = "https://token-cdn-domain/{id}.json/";

        await factory.createNewToken(tokenName, tokenSymbol, baseUri);
        
        // get nft address
        const events = await factory.queryFilter(factory.filters.TokenCreated(), 0, "latest");
        expect(events[0].args.creator).to.be.eq(await owner.getAddress());
        const nftAddress = events[0].args.token;
        const erc721Contract = new ethers.Contract(nftAddress, ERC721Abi, owner);

        await erc721Contract.mint(await owner.getAddress(), 3);

        const nftNumber = await factory.accountDeploymentNumber(await owner.getAddress());
        const nftDeployments = await factory.getAccountDeployments(await owner.getAddress());
        const nftDeployment = await factory.getAccountDeployment(await owner.getAddress(), Number(nftNumber) - 1);

        expect(nftNumber).to.be.eq(1);
        expect(nftDeployments[0]).to.be.eq(nftAddress);
        expect(nftDeployment).to.be.eq(nftAddress);
        expect(await erc721Contract.ownerOf(0)).to.be.eq(await owner.getAddress());
    });
})