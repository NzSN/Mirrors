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
  if (argc < 2) return 2;
  std::wstring command;
  for (int i = 1; i < argc; ++i) {
    if (i != 1) command += L" ";
    command += quote(argv[i]);
  }
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof limits)) {
    if (job) CloseHandle(job);
    return 2;
  }
  STARTUPINFOW startup{};
  startup.cb = sizeof startup;
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(argv[1], command.data(), nullptr, nullptr, TRUE,
                      CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr, &startup, &child)) {
    CloseHandle(job);
    return 2;
  }
  if (!AssignProcessToJobObject(job, child.hProcess) || ResumeThread(child.hThread) == DWORD(-1)) {
    TerminateProcess(child.hProcess, 2);
    WaitForSingleObject(child.hProcess, INFINITE);
    CloseHandle(child.hThread);CloseHandle(child.hProcess);CloseHandle(job);
    return 2;
  }
  CloseHandle(child.hThread);
  WaitForSingleObject(child.hProcess, INFINITE);
  DWORD code = 2;
  GetExitCodeProcess(child.hProcess, &code);
  CloseHandle(child.hProcess);
  JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
  bool observed = false;
  for (int i = 0; i < 40; ++i) {
    observed = QueryInformationJobObject(job, JobObjectBasicAccountingInformation,
                                        &accounting, sizeof accounting, nullptr) != 0;
    if (!observed || accounting.ActiveProcesses == 0) break;
    Sleep(50);
  }
  std::cerr << "TASK JOB CLEANUP active=" << (observed ? std::to_string(accounting.ActiveProcesses) : "unknown") << "\n";
  if (!observed || accounting.ActiveProcesses != 0) code = 2;
  CloseHandle(job); // Enforce containment even when the test's cleanup failed.
  return static_cast<int>(code);
}
