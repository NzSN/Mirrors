# Generated DPM integration checklist

Copy application behavior into your own module outside this generated tree.
1. Admit the modelSemanticDigest/mappingSha256 constants and your actual implementation hash.
2. Use generated actors/checkpoints in the SDK adapter; implement its deferred factory.
3. Insert actual arrive(checkpoint) calls at safe points inside owned workers.
4. initialize -> session.initialize(); transition -> session.advance(step_for/stepFor(actionId, actor)).
5. Observe actual application state through the ordinary generated typed port.
6. Dispose once and retain primary comparison plus cleanup independently.

Actor input arguments refer to explicit generated input IDs in DpmKit.plan.json.
Fixed actors need no actor argument; disagreement is rejected.
The kit does not infer behavior, inject hooks or initialize from expected model state.
