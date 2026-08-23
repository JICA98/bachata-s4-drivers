/* Minimal Mesa tu_knl_kgsl.cc excerpt: stock wait_timestamp_safe (Mesa 26.1 / mojo-26.1 / gen8 / mojo-25.0). */

static inline bool
timestamp_cmp(uint32_t a, uint32_t b)
{
   return (int32_t) (a - b) >= 0;
}

static int
get_relative_ms(uint64_t abs_timeout_ns)
{
   if (abs_timeout_ns >= INT64_MAX)
      /* We can assume that a wait with a value this high is a forever wait
       * and return -1 here as it's the infinite timeout for ppoll() while
       * being the highest unsigned integer value for the wait KGSL IOCTL
       */
      return -1;

   uint64_t cur_time_ms = os_time_get_nano() / 1000000;
   uint64_t abs_timeout_ms = abs_timeout_ns / 1000000;
   if (abs_timeout_ms <= cur_time_ms)
      return 0;

   return abs_timeout_ms - cur_time_ms;
}

/* safe_ioctl is not enough as restarted waits would not adjust the timeout
 * which could lead to waiting substantially longer than requested
 */
static VkResult
wait_timestamp_safe(int fd,
                    unsigned int context_id,
                    unsigned int timestamp,
                    uint64_t abs_timeout_ns)
{
   struct kgsl_device_waittimestamp_ctxtid wait = {
      .context_id = context_id,
      .timestamp = timestamp,
      .timeout = get_relative_ms(abs_timeout_ns),
   };

   while (true) {
      int ret = ioctl(fd, IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID, &wait);

      if (ret == -1 && (errno == EINTR || errno == EAGAIN)) {
         int timeout_ms = get_relative_ms(abs_timeout_ns);

         /* update timeout to consider time that has passed since the start */
         if (timeout_ms == 0)
            return VK_TIMEOUT;

         wait.timeout = timeout_ms;
      } else if (ret == -1) {
         assert(errno == ETIMEDOUT);
         return VK_TIMEOUT;
      } else {
         return VK_SUCCESS;
      }
   }
}
