// Task-owned adapter: execute the exact selected Java/JAR without shell parsing.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <iostream>
#include <string>

static std::wstring quote(const std::wstring& argument) {
  std::wstring output = L"\"";
  std::size_t slashes = 0;
  for (wchar_t c : argument) {
    if (c == L'\\') { ++slashes; continue; }
    output.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
    output += c;
    slashes = 0;
  }
  output.append(slashes * 2, L'\\');
  output += L'"';
  return output;
}

int wmain(int argc, wchar_t** argv) {
  const std::wstring java = L"D:\\Programs\\jdk-25.0.4+7\\bin\\java.exe";
  const std::wstring jar = L"D:\\ModelMirrors\\staging\\qualification-rc7-20261105\\runtime-inputs\\apalache.jar";
  std::wstring command = quote(java) + L" -jar " + quote(jar);
  for (int i = 1; i < argc; ++i) command += L" " + quote(argv[i]);
  STARTUPINFOW startup{};
  startup.cb = sizeof startup;
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION child{};
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                       &limits, sizeof limits)) {
    if (job) CloseHandle(job);
    return 2;
  }
  if (!CreateProcessW(java.c_str(), command.data(), nullptr, nullptr, TRUE,
                      CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr, &startup, &child)) {
    std::cerr << "selected Java launch failed: " << GetLastError() << "\n";
    CloseHandle(job);
    return 2;
  }
  // Establish ownership before Java can spawn workers. Terminating this
  // adapter closes its non-inherited job handle and kills every descendant.
  if (!AssignProcessToJobObject(job, child.hProcess) || ResumeThread(child.hThread) == DWORD(-1)) {
    std::cerr << "selected Java job admission failed: " << GetLastError() << "\n";
    TerminateProcess(child.hProcess, 2);
    WaitForSingleObject(child.hProcess, INFINITE);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    CloseHandle(job);
    return 2;
  }
  CloseHandle(child.hThread);
  WaitForSingleObject(child.hProcess, INFINITE);
  DWORD code = 2;
  GetExitCodeProcess(child.hProcess, &code);
  CloseHandle(child.hProcess);
  CloseHandle(job);
  return static_cast<int>(code);
}
