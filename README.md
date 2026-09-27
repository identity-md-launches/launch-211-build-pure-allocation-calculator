# Exact allocation calculator

A standalone Solidity **0.8.24** Foundry project. `AllocationCalculator` is stateless, has no constructor arguments, and only calculates numbers. It creates no token, holds no accounting balances, grants no roles, and makes no external calls or transfers.

**Deployment is ON; Sepolia deployment is incomplete.** The release script defaults to enabled and rejects every chain except **11155111**. No funded signer or RPC configuration was supplied to this workspace, so no deployment transaction has been submitted. The address, transaction hash, and explorer link are intentionally `null` in [`deployments/sepolia.json`](deployments/sepolia.json). Local deployment tests do not constitute a Sepolia deployment.

## Interface and exact behavior

```solidity
function allocate(
    uint256 amount,
    address[] calldata recipients,
    uint256[] calldata weights
) external pure returns (uint256[] memory allocations);
```

- Accepts 1 through 16 distinct, nonzero recipient addresses. EOAs and contracts are both valid; no ownership or code checks are made.
- Requires one positive `uint256` integer weight per recipient. The mathematical sum of weights must fit in `uint256`; totals larger than `2^256 - 1` are rejected, not wrapped or rescaled.
- Accepts every `uint256` amount, including zero and `2^256 - 1`. Zero amounts still undergo all validation.
- Let `T = sum(weights)`. Start with `q[i] = floor(amount * weights[i] / T)` and exact remainder `r[i] = (amount * weights[i]) mod T`.
- Give one additional unit to the first `amount - sum(q)` recipients in order of descending `r[i]`, with equal remainders ordered by ascending **original array index**. Each recipient gets at most one additional unit.
- Return the amounts in the original input order. Inputs are neither reordered nor modified. Results are deterministic, independent of caller, time, chain state, and address magnitude.

This is the largest-remainder (Hamilton) method. Integer units have no built-in currency or decimals. The caller chooses the unit. Permuting paired addresses and weights preserves the per-address result when remainders are distinct. When a tie crosses the bonus cutoff, the new input order determines the winner; permutation invariance is deliberately not promised for ties.

Validation order is recipient count, array lengths, then an ascending-index scan checking zero address, duplicate against earlier indices, zero weight, and cumulative weight overflow. The first error encountered reverts the entire call:

| Error | Meaning |
| --- | --- |
| `InvalidRecipientCount(count)` | Count is outside 1..16 |
| `LengthMismatch(recipients, weights)` | Array lengths differ |
| `ZeroRecipient(index)` | Zero address |
| `DuplicateRecipient(firstIndex, duplicateIndex)` | Repeated address |
| `ZeroWeight(index)` | Weight is zero |
| `TotalWeightOverflow()` | Weight sum would exceed `uint256` |

Addresses are compared as their 160-bit values. Negative or fractional weights are outside the ABI domain. Zero address is invalid even if its calculated allocation would be zero.

## Overflow handling and conservation proof

[`FullMath.sol`](src/FullMath.sol) implements exact floor division of a **512-bit** product by a 256-bit denominator. It reconstructs both product limbs using `mul` and `mulmod`, subtracts the remainder, removes powers of two, and divides by the odd denominator using its inverse modulo `2^256`. The `unchecked` block is confined to this modular arithmetic; its wrapping is intentional. The implementation uses the technique described by [Remco Bloemen](https://xn--2-umb.com/21/muldiv/).

There is no intermediate `amount * weight` in ordinary 256-bit Solidity arithmetic. `mulmod(amount, weight, T)` supplies the exact remainder independently of product overflow. The library rejects zero denominators and quotients that do not fit, but neither error can arise from valid calculator inputs: `T > 0`, `weight <= T`, and therefore each quotient is at most `amount`. All calculator additions and subtractions remain checked.

For each recipient, Euclidean division gives, over mathematical integers:

```text
A * w[i] = T * q[i] + r[i], where 0 <= r[i] < T.
Summing: A * T = T * sum(q[i]) + sum(r[i]).
Thus U = A - sum(q[i]) = sum(r[i]) / T is an integer, and 0 <= U < n.
```

The pair `(remainder descending, index ascending)` defines a strict total order, so its ranks are exactly `0..n-1`. The implementation awards one unit precisely to ranks below `U`, hence exactly `U` units. Consequently:

```text
sum(outputs) = sum(q[i]) + U = A.
```

If there are `p` positive remainders, `sum(r[i]) < p*T`, so `U < p` whenever `U > 0`; no zero remainder receives a bonus. Every floor sum and partial sum is at most `A`, which prevents accumulator overflow. Any bonus recipient has a floor below `A`, so its increment also fits, including when `A = uint256.max`. All outputs lie between their floor and ceiling quotas.

Validation and remainder ranking each take at most `n^2` comparisons with `n <= 16`; memory usage is O(n). Work is bounded independently of the amount and weight magnitudes.

## Offline reproduction

Prerequisites: Foundry (`forge`, and `cast` for deployment), with the native **solc 0.8.24** compiler installed in Foundry's compiler cache. There are **no package, submodule, forge-std, npm, or fetched test dependencies**. All contract and test source is included. `foundry.toml` pins `solc_version = "0.8.24"` by version, not executable path; optimizer runs are 200, EVM target is Paris, and bytecode metadata is disabled. FFI is disabled and Solidity filesystem permissions are empty.

With the toolchain installed, these commands require no network or RPC:

```sh
forge build --offline
forge test --offline
forge fmt --check
```

Plain `forge build` and `forge test` use the same cached compiler. A machine without solc 0.8.24 needs that toolchain component installed before going offline; the project does not download dependencies during a test. To prepare a writable compiler cache on this workspace, where the default home directory is read-only, the following was used (the first build requires network only if the compiler is missing):

```sh
mkdir -p /tmp/allocation-toolchain
XDG_DATA_HOME=/tmp/allocation-toolchain forge build
XDG_DATA_HOME=/tmp/allocation-toolchain forge build --offline
XDG_DATA_HOME=/tmp/allocation-toolchain forge test --offline
forge fmt --check
```

This selects a normal Foundry compiler cache and does not override the pinned compiler version. It assumes no existing `~/.svm` directory takes precedence over XDG. The compiler remains a toolchain prerequisite, not a Solidity dependency.

The suite uses a minimal local cheatcode interface. It never reads RPC state, accesses signing keys, uses FFI/filesystem cheatcodes, or calls `vm.setEnv`. Fuzzing uses the fixed seed in `foundry.toml` and 512 runs per fuzz test. Validation with Forge 1.8.3 and solc 0.8.24 passed: **32 tests, 0 failures, 0 skips**, a forced offline build, and `forge fmt --check`. Coverage includes:

- Concrete zero/tiny/exact-divisibility examples, equal and unequal ties, all six permutations of an unequal-weight example, and changed index priorities under ties.
- 1 and 16 recipients; maximum amount, maximum weight total, and the 16 amounts nearest `uint256.max`.
- Every validation error, duplicate positions, both length-mismatch directions, and validation for zero amounts.
- Full-width random conservation, quota, and remainder ordering, using an independent 256-step binary long-division oracle with no `mulmod`, assembly, or modular inverse.
- A bounded native-product reference, permutation fuzzing, and arithmetic branch tests for high products, borrow, power-of-two denominators, division by zero, and quotient overflow.
- Rejection of ETH, unchanged recipient balances, runtime size, and absence of state writes, external calls, contract creation, and escape opcodes in the calculator runtime.
- Deployment configuration enabled on a simulated Sepolia chain and rejected on mainnet, local chain ID 31337, and when disabled.

Forge may emit the `require-revert-in-loop` performance lint: early validation reverts in bounded loops are intentional.

## Demo parameters and accounts

The test/demo recipient accounts are identifiers only. No private keys or balances are needed to calculate an allocation:

| Index | Recipient | Weight | Output for amount 10 |
| --- | --- | --- | --- |
| 0 | `0x0000000000000000000000000000000000001001` | 1 | 2 |
| 1 | `0x0000000000000000000000000000000000001002` | 2 | 3 |
| 2 | `0x0000000000000000000000000000000000001003` | 3 | 5 |

The floors are `[1,3,5]`, remainders `[4,2,0]`, and the one remaining unit goes to index 0. For amount 2 the result is `[0,1,1]`. With amount 2 and weights `[1,1,1]`, the result is `[1,1,0]`.

Run these examples offline with:

```sh
forge test --offline --match-test 'test(UnequalWeightsDemo|TinyAmountsAndTies)'
```

## Sepolia deployment and operations

[`script/Deploy.s.sol`](script/Deploy.s.sol) creates only `AllocationCalculator`, with **constructor arguments `[]` (ABI encoding `0x`)**, transaction value **0 wei**, and no initialization step. Deployment defaults to **ON**. `DEPLOYMENT_ENABLED=false` stops the script. Its chain check occurs before broadcasting or contract creation. The calculator has no owner, administrator, minting authority, upgrade hook, or linked libraries. The deployer's identity has no effect on runtime behavior.

Use a dedicated, funded Sepolia test account stored in a local Foundry keystore. Do not reuse the demo recipient identifiers as signing accounts. Supply the actual account name and RPC endpoint through the invoking shell; no `.env` file is required:

```sh
export SEPOLIA_RPC_URL='https://your-sepolia-rpc'
export DEPLOYER_ACCOUNT='your-sepolia-test-keystore-name'
export DEPLOYMENT_ENABLED=true

forge build --offline
forge test --offline
forge fmt --check
cast chain-id --rpc-url "$SEPOLIA_RPC_URL" # must report 11155111

# Simulate without submitting a transaction.
forge script script/Deploy.s.sol:Deploy --offline \
  --rpc-url "$SEPOLIA_RPC_URL" --account "$DEPLOYER_ACCOUNT"

# Submit the tested deployment. The script itself rejects any non-Sepolia chain.
forge script script/Deploy.s.sol:Deploy --offline \
  --rpc-url "$SEPOLIA_RPC_URL" --account "$DEPLOYER_ACCOUNT" \
  --broadcast --confirmations 2
```

Here `--offline` controls compiler acquisition; a broadcast still requires RPC access and Sepolia ETH for gas. Foundry can prompt for the keystore password. Do not put secrets into source files or the deployment record. If using the writable compiler cache above, prefix each Forge command with `XDG_DATA_HOME=/tmp/allocation-toolchain`.

After a successful broadcast, retain the transaction and receipt from `broadcast/Deploy.s.sol/11155111/run-latest.json`, confirm receipt status is successful, and compare on-chain bytecode with the local artifact:

```sh
# Set these from the actual successful deployment receipt.
export ALLOCATION_ADDRESS='0x...'
export ALLOCATION_TX_HASH='0x...'
cast receipt "$ALLOCATION_TX_HASH" --rpc-url "$SEPOLIA_RPC_URL"
cast code "$ALLOCATION_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL"
forge inspect src/AllocationCalculator.sol:AllocationCalculator deployedBytecode --offline
cast call "$ALLOCATION_ADDRESS" \
  'allocate(uint256,address[],uint256[])(uint256[])' 10 \
  '[0x0000000000000000000000000000000000001001,0x0000000000000000000000000000000000001002,0x0000000000000000000000000000000000001003]' \
  '[1,2,3]' --rpc-url "$SEPOLIA_RPC_URL"
```

Update `deployments/sepolia.json` with the confirmed address, transaction hash, status, and `https://sepolia.etherscan.io/address/<address>` link; the transaction link is `https://sepolia.etherscan.io/tx/<hash>`. Do not label a predicted address or a local simulation as a deployment. Explorer source verification is a separate, currently incomplete operation.

The tested runtime is 1,877 bytes with keccak256 `0xaf849b2b82140da098ca0f23637bafca2f07f42ac2adee465f31873d019d0273`, also recorded in the deployment file. This is a local bytecode fingerprint, not an on-chain address. Public `eth_chainId` probes to `https://ethereum-sepolia-rpc.publicnode.com` and `https://rpc.sepolia.org` both returned HTTP 403 in this environment; a working RPC and funded signer are still required.

Operational responsibility rests with the operator for signer custody, testnet funding, RPC selection, gas fees, receipt/finality checks, and matching the deployed bytecode to the tested artifact. No mainnet transaction is part of this project. No transfer system or token launch is included.

## Assumptions and incomplete checks

The weight-sum ceiling is an explicit input-domain limit; arbitrary-precision sums beyond 256 bits are unsupported. The caller controls recipient order and can therefore choose tie priority. Split calls can produce different rounded results from one combined call, and the Hamilton method does not guarantee that each recipient's allocation increases monotonically as the total amount changes. Consumers must choose their batching and ordering policy accordingly.

Normal ETH transfers and value-bearing calls revert. ETH forcibly sent to the contract cannot be recovered, as there is no withdrawal mechanism. Consumers are responsible for any actual payments and must not infer that a returned allocation authorizes a transfer.

The mathematical conservation argument and deterministic/fuzz tests are not a machine-checked formal verification or independent security audit. Random testing is not exhaustive over all 256-bit inputs. The environment-reading and broadcast portion of `run()` has not been exercised against a live signer; tests invoke `deploy(Config)` directly without changing process environment. Sepolia submission, live bytecode comparison, finality, and explorer source verification remain incomplete until deployment credentials are supplied.

The supplied pinned `Project.protected.t.sol` and `Token.protected.t.sol` were read. They are generic Solidity 0.8.26 token-launch checks requiring external manifest/environment data and forge-std; they do not define an allocation interface. They were not copied into this 0.8.24 project or claimed as passing. The explicit task requires no token, so no token or token-launch manifest was created. The project's own tests cover the allocation requirements and relevant application-runtime checks.
