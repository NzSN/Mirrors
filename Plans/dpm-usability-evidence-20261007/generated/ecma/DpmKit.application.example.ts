// Copy to your application; implement actual behavior outside generated files.
import type { ScheduleBindingSession } from 'mirrorecma';
import { stepFor } from './DpmKit.generated.js';
export function callbacks(session: ScheduleBindingSession) {
  return {initialize: () => session.initialize(),
    transition: (action: string, actor?: string) => session.advance(stepFor(action, actor)),
    observation: () => session.observation(), dispose: () => session.dispose()};
}
// Handwritten generated public port forwards its typed actor input to transition.
// Provide actual Node-worker hooks and convert real observations to the model-native shape.
