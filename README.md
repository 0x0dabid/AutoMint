# AutoMint — NFT Launchpad with Persistent Agents on Ritual Chain

Autonomous NFT minting on [Ritual Chain](https://ritualfoundation.org) (ID: 1979).
Users deploy per-user **Persistent Agent** contracts that mint NFTs on schedule — even while offline.

---

## Architecture

```
User → AutoMintFactory.createAgent()
           ↓
    AutoMintAgent (Persistent Agent)
           ↓
    Registers on AgentHeartbeat (0xEF50...)
    Registers on PersistentAgent precompile (0x0820)
           ↓
    Scheduler.schedule(wakeUp, interval)
           ↓
    wakeUp() fires top-of-block via SystemTx
           ↓
    SovereignAgent precompile (0x080C) → TEE mint execution
           ↓
    onSovereignAgentResult() ← AsyncDelivery callback
           ↓
    _scheduleNext() + _postHeartbeat() → loop
```

## System Contracts (Ritual Chain)

| Contract          | Address                                      |
|-------------------|----------------------------------------------|
| Scheduler         | `0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B` |
| RitualWallet      | `0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948` |
| AsyncJobTracker   | `0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5` |
| AsyncDelivery     | `0x5A16214fF555848411544b005f7Ac063742f39F6` |
| AgentHeartbeat    | `0xEF505E801f1Db392B5289690E2ffc20e840A3aCa` |
| TEEServiceReg     | `0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F` |
| ModelPricingReg   | `0x7A85F48b971ceBb75491b61abe279728F4c4384f` |

## Precompiles Used

| Precompile           | Address  | Purpose                            |
|----------------------|----------|------------------------------------|
| Persistent Agent     | `0x0820` | Long-running agent + heartbeat     |
| Sovereign Agent      | `0x080C` | TEE-executed mint logic            |
| SECP256R1 (Passkey)  | `0x0100` | WebAuthn P-256 signature verify    |

---

## Contracts (`contracts/`)

| Contract              | Description                                    |
|-----------------------|------------------------------------------------|
| `AutoMintFactory.sol` | Deploys `AutoMintAgent` clones per user        |
| `AutoMintAgent.sol`   | Persistent agent — schedules, wakes, mints     |
| `MintConditions.sol`  | `SupplyGate`, `PriceGate`, `TimeGate`, `Composite` |
| `SampleNFT.sol`       | ERC-721 for end-to-end testing                 |

### Compile

```bash
# Uses offline solc via Node.js (no download required)
node contracts/compile.js

# Or with Foundry (requires solc download on first run):
cd contracts && forge build
```

### Test

```bash
cd contracts && forge test -v
```

### Deploy to Ritual Chain

```bash
cp .env.example .env
# Fill in PRIVATE_KEY

cd contracts
forge script script/Deploy.s.sol \
  --rpc-url https://rpc.ritualfoundation.org \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

### Create an Agent (after deploy)

```bash
FACTORY=<deployed_factory_addr> NFT=<nft_addr> \
  forge script script/CreateAgent.s.sol \
  --rpc-url https://rpc.ritualfoundation.org \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## Frontend (`frontend/`)

Next.js 14 App Router + wagmi v2 + viem, configured for Ritual Chain.

### Run locally

```bash
cd frontend
cp .env.example .env.local
# Fill in contract addresses after deployment

npm install
npm run dev
```

### Build

```bash
npm run build
```

### Deploy to Vercel

```bash
vercel --prod
```

### Pages

| Route               | Description                                         |
|---------------------|-----------------------------------------------------|
| `/`                 | Dashboard — list of user's agents with live status  |
| `/create`           | Deploy a new AutoMint agent with full config form   |
| `/agents/[address]` | Agent detail — controls, execution log, heartbeat   |
| `/gallery`          | NFT gallery — transfer NFTs out of agent contracts  |

---

## Mint Conditions

Deploy condition contracts for conditional minting:

```solidity
// Only mint when supply < 9000
SupplyGateCondition gate = new SupplyGateCondition(9000);

// Only mint when price <= 0.01 RITUAL
PriceGateCondition gate = new PriceGateCondition(0.01 ether);

// Only mint between 2am-4am UTC
TimeGateCondition gate = new TimeGateCondition(7200, 14400);

// AND/OR compose
CompositeCondition gate = new CompositeCondition([addr1, addr2], Logic.AND);
```

Pass the condition address when creating an agent — the Scheduler skips executions where the condition returns false (no fee consumed).

---

## Agent Lifecycle

1. **Deploy**: `factory.createAgent(nft, selector, args, interval, maxExecutions, condition)`
2. **Fund**: send RITUAL to the agent contract to cover mint prices
3. **Start**: `agent.start(initialDelay)` — registers on heartbeat, schedules first wakeUp
4. **Running**: Scheduler calls `wakeUp()` top-of-block at each interval
5. **TEE**: SovereignAgent precompile executes mint in TEE, result delivered via AsyncDelivery
6. **Heartbeat**: Agent posts heartbeat every 100 blocks → shows Active on `explorer.ritualfoundation.org/agents`
7. **Complete**: After `maxExecutions`, agent stops automatically
8. **Cancel**: `agent.cancel()` stops and refunds remaining escrowed fees

---

## E2E Test Checklist

- [ ] Deploy AutoMintFactory
- [ ] Deploy SampleNFT
- [ ] Create agent via factory
- [ ] Fund agent with RITUAL
- [ ] Start agent
- [ ] Verify agent appears Active on explorer
- [ ] Wait for Scheduler to fire wakeUp
- [ ] Verify NFT minted in agent's wallet
- [ ] Verify heartbeat posted on-chain
- [ ] Transfer NFT to user wallet via gallery
- [ ] Cancel agent and verify refund
- [ ] Verify agent shows Stopped on explorer
