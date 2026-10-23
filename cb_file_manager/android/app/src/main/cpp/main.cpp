#include <chrono>
#include <csignal>
#include <thread>
#include <unistd.h>

int llama_server(int argc, char ** argv);

int main(int argc, char ** argv) {
    // Watch the parent process, including during model loading. PDEATHSIG is
    // tied to the spawning *thread*, which a Dart I/O worker may retire while
    // Flutter is still alive (see PR_SET_PDEATHSIG(2)'s caveat).
    const auto parent = getppid();
    if (parent <= 1) {
        return 1;
    }
    std::thread([parent] {
        while (getppid() == parent) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
        kill(getpid(), SIGKILL);
    }).detach();
    return llama_server(argc, argv);
}
