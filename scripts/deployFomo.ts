import { toNano } from '@ton/core';
import { Fomo } from '../wrappers/Fomo';
import { NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const fomo = provider.open(await Fomo.fromInit(BigInt(Math.floor(Math.random() * 10000))));

    await fomo.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(fomo.address);

    console.log('ID', await fomo.getId());
}
