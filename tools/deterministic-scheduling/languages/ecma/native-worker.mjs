export async function run({commands}, checkpoint) {
  for (const command of commands) {
    const actual = await checkpoint.request(command);
    await checkpoint.arrive(actual.phase);
  }
}
