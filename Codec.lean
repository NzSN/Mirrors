import Codec.Json
import Codec.ExplorerRpc
import Codec.Bridge
import Codec.Consul
import Codec.StrictJson
import Codec.ModelInterfaceJson
import Codec.ModelInterfaceDistributionJson

/-!
# Layer 1: total JSON codecs (design §5.2)

Umbrella module for the payload layer: the ITF value codec with §6.6
round-trip proofs (Codec.Json), the explorer JSON-RPC wire codec
(Codec.ExplorerRpc), the Core↔Codec message bridge (Codec.Bridge), and
the Consul registry payload codec (Codec.Consul). -/
