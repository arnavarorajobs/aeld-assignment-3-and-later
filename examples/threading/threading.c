#include "threading.h"
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>

#define _POSIX_C_SOURCE 200809L

// Optional: use these functions to add debug or error prints to your application
#define DEBUG_LOG(msg,...)
//#define DEBUG_LOG(msg,...) printf("threading: " msg "\n" , ##__VA_ARGS__)
#define ERROR_LOG(msg,...) printf("threading ERROR: " msg "\n" , ##__VA_ARGS__)

static bool sleep_ms(int milliseconds)
{
    if (milliseconds < 0) {
        return false;
    }

    struct timespec delay = {
        .tv_sec = milliseconds / 1000,
        .tv_nsec = (milliseconds % 1000) * 1000000L
    };
    struct timespec remaining;

    while (nanosleep(&delay, &remaining) == -1) {
        if (errno != EINTR) {
            return false;
        }
        delay = remaining;
    }

    return true;
}


void* threadfunc(void* thread_param)
{

    // TODO: wait, obtain mutex, wait, release mutex as described by thread_data structure
    // hint: use a cast like the one below to obtain thread arguments from your parameter
    //struct thread_data* thread_func_args = (struct thread_data *) thread_param;
    struct thread_data *data = (struct thread_data *)thread_param;

    if (data == NULL){
        return NULL;;
    }

    data->thread_complete_success = false;

    if (data->mutex == NULL || !sleep_ms(data->wait_to_obtain_ms)){
        return data;
    }

    if (pthread_mutex_lock(data->mutex) != 0){
        return data;
    }

    bool hold_succeeded = sleep_ms(data->wait_to_release_ms);
    bool unlock_succeeded = (pthread_mutex_unlock(data->mutex) == 0);

    data->thread_complete_success = hold_succeeded && unlock_succeeded;

    return thread_param;
}


bool start_thread_obtaining_mutex(pthread_t *thread, pthread_mutex_t *mutex,int wait_to_obtain_ms, int wait_to_release_ms)
{
    /**
     * TODO: allocate memory for thread_data, setup mutex and wait arguments, pass thread_data to created thread
     * using threadfunc() as entry point.
     *
     * return true if successful.
     *
     * See implementation details in threading.h file comment block
     */
    if (thread == NULL || mutex == NULL || wait_to_obtain_ms < 0 || wait_to_release_ms <0){
        return false;
    }

    struct thread_data *data = malloc(sizeof(*data));
    if (data == NULL){
        return false;
    }

    data->mutex = mutex;
    data->wait_to_obtain_ms = wait_to_obtain_ms;
    data->wait_to_release_ms = wait_to_release_ms;
    data->thread_complete_success = false;

    int result = pthread_create(thread, NULL, threadfunc, data);
    if (result != 0){
        free(data);
        return false;
    }

    return true;
    
}

