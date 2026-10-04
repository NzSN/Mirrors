// Controller-only adapter around the selected native phase worker. Production
// hooks keep their preallocated atomic handshake; no MirrorCPP mutex enters VEH.
#include <memory>
#include <fstream>
#include <filesystem>
#include <iomanip>
#include <sstream>
#define main writesentry_original_phase_main
#include "phase_worker.cpp"
#undef main
#include <bcrypt.h>

namespace {
std::pair<std::string, std::string> executable_identity() {
  std::array<wchar_t, 32'768> path{};
  const DWORD length = ::GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length >= path.size()) throw std::runtime_error("native image path unavailable");
  const int count = ::WideCharToMultiByte(CP_UTF8, 0, path.data(), static_cast<int>(length), nullptr, 0, nullptr, nullptr);
  if (count <= 0) throw std::runtime_error("native image path encoding failed");
  std::string encoded(static_cast<std::size_t>(count), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, path.data(), static_cast<int>(length), encoded.data(), count, nullptr, nullptr);
  struct Hash {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    ~Hash() { if (hash) BCryptDestroyHash(hash); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
  } hash;
  if (BCryptOpenAlgorithmProvider(&hash.algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0)
    throw std::runtime_error("native hash provider unavailable");
  DWORD size = 0, returned = 0;
  if (BCryptGetProperty(hash.algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&size), sizeof(size), &returned, 0) < 0 || size > 1'048'576)
    throw std::runtime_error("native hash object invalid");
  std::vector<UCHAR> object(size);
  if (BCryptCreateHash(hash.algorithm, &hash.hash, object.data(), size, nullptr, 0, 0) < 0)
    throw std::runtime_error("native hash initialization failed");
  std::ifstream file(std::filesystem::path(path.data()), std::ios::binary);
  if (!file) throw std::runtime_error("native image cannot be opened");
  std::array<char, 65'536> buffer{};
  while (file.read(buffer.data(), buffer.size()) || file.gcount())
    if (BCryptHashData(hash.hash, reinterpret_cast<PUCHAR>(buffer.data()), static_cast<ULONG>(file.gcount()), 0) < 0)
      throw std::runtime_error("native image hash failed");
  std::array<UCHAR, 32> bytes{};
  if (BCryptFinishHash(hash.hash, bytes.data(), static_cast<ULONG>(bytes.size()), 0) < 0)
    throw std::runtime_error("native image hash finalization failed");
  std::ostringstream digest;
  for (const auto byte : bytes) digest << std::hex << std::setfill('0') << std::setw(2) << static_cast<unsigned>(byte);
  return {encoded, digest.str()};
}
bool read_line(std::string& line) {
  line.clear();
  for (char ch; std::cin.get(ch);) {
    if (ch == '\n') return true;
    if (line.size() == 65'535) throw std::runtime_error("native request exceeds bound");
    line.push_back(ch);
  }
  if (!line.empty()) throw std::runtime_error("truncated native request");
  return false;
}
nlohmann::json identity() {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!::GetProcessTimes(::GetCurrentProcess(), &created, &exited, &kernel, &user))
    throw std::runtime_error("native process identity unavailable");
  const auto time = (static_cast<uint64_t>(created.dwHighDateTime) << 32) | created.dwLowDateTime;
  const auto image = executable_identity();
  return {{"imagePath", image.first}, {"imageSha256", image.second}, {"processId", ::GetCurrentProcessId()}, {"createdFileTime", std::to_string(time)},
          {"actors", {{"t1", phase_native::actors[0].id}, {"t2", phase_native::actors[1].id}}}};
}
}
int main() {
  try {
    auto runtime = std::make_unique<phase_native::Runtime>();
    nlohmann::json admitted;
    for (std::string line; read_line(line);) {
      if (line.size() > 65'535) throw std::runtime_error("native request exceeds bound");
      const auto request = nlohmann::json::parse(line);
      if (request.at("op") == "Quit") {
        if (admitted.is_null()) throw std::runtime_error("native worker not initialized");
        runtime.reset(); // Destructor verifies owned actor termination.
        std::cout << nlohmann::json{{"closed", true}, {"nativeIdentity", admitted}}.dump() << '\n' << std::flush;
        return 0;
      }
      auto response = runtime->request(request);
      if (request.at("op") == "Initialize") admitted = identity();
      if (admitted.is_null() || identity() != admitted) throw std::runtime_error("native actor identity changed");
      response["nativeIdentity"] = admitted;
      std::cout << response.dump() << '\n' << std::flush;
    }
    // EOF still runs owned cleanup, but is not a positive Quit acknowledgement.
    return 2;
  } catch (const std::exception& error) {
    std::cout << nlohmann::json{{"error", error.what()}}.dump() << '\n' << std::flush;
    return 2;
  }
}
