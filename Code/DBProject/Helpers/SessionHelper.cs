using System;
using System.Web;
using StackExchange.Redis;
using Newtonsoft.Json;

namespace DBProject.Helpers
{
    /// <summary>
    /// Session helper that abstracts session state management for containerization.
    /// Uses Redis for distributed session state when configured, falls back to InProc for local development.
    /// </summary>
    public static class SessionHelper
    {
        private static Lazy<ConnectionMultiplexer> _lazyConnection = new Lazy<ConnectionMultiplexer>(() =>
        {
            string redisConnection = Environment.GetEnvironmentVariable("REDIS_CONNECTION_STRING");
            if (string.IsNullOrEmpty(redisConnection))
            {
                // Fallback for local development - will use InProc session
                return null;
            }
            return ConnectionMultiplexer.Connect(redisConnection);
        });

        private static ConnectionMultiplexer Connection => _lazyConnection.Value;
        private static IDatabase RedisDb => Connection?.GetDatabase();

        /// <summary>
        /// Gets a session value by key
        /// </summary>
        public static T GetSession<T>(string key)
        {
            if (HttpContext.Current == null)
                return default(T);

            // Try Redis first if available
            if (RedisDb != null && HttpContext.Current.Session != null)
            {
                string sessionId = HttpContext.Current.Session.SessionID;
                string redisKey = $"session:{sessionId}:{key}";
                
                try
                {
                    var value = RedisDb.StringGet(redisKey);
                    if (value.HasValue)
                    {
                        if (typeof(T) == typeof(string))
                            return (T)(object)value.ToString();
                        
                        return JsonConvert.DeserializeObject<T>(value);
                    }
                }
                catch (Exception ex)
                {
                    // Log error and fall back to InProc session
                    System.Diagnostics.Debug.WriteLine($"Redis error: {ex.Message}");
                }
            }

            // Fallback to InProc session
            if (HttpContext.Current.Session != null && HttpContext.Current.Session[key] != null)
            {
                return (T)HttpContext.Current.Session[key];
            }

            return default(T);
        }

        /// <summary>
        /// Sets a session value by key
        /// </summary>
        public static void SetSession<T>(string key, T value)
        {
            if (HttpContext.Current == null || HttpContext.Current.Session == null)
                return;

            // Set in InProc session (for backward compatibility)
            HttpContext.Current.Session[key] = value;

            // Also set in Redis if available
            if (RedisDb != null)
            {
                string sessionId = HttpContext.Current.Session.SessionID;
                string redisKey = $"session:{sessionId}:{key}";
                
                try
                {
                    string serializedValue;
                    if (value is string)
                        serializedValue = value.ToString();
                    else
                        serializedValue = JsonConvert.SerializeObject(value);

                    RedisDb.StringSet(redisKey, serializedValue, TimeSpan.FromMinutes(20));
                }
                catch (Exception ex)
                {
                    // Log error but don't fail - InProc session is still set
                    System.Diagnostics.Debug.WriteLine($"Redis error: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Removes a session value by key
        /// </summary>
        public static void RemoveSession(string key)
        {
            if (HttpContext.Current == null || HttpContext.Current.Session == null)
                return;

            // Remove from InProc session
            HttpContext.Current.Session.Remove(key);

            // Remove from Redis if available
            if (RedisDb != null)
            {
                string sessionId = HttpContext.Current.Session.SessionID;
                string redisKey = $"session:{sessionId}:{key}";
                
                try
                {
                    RedisDb.KeyDelete(redisKey);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Redis error: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Clears all session data
        /// </summary>
        public static void ClearSession()
        {
            if (HttpContext.Current == null || HttpContext.Current.Session == null)
                return;

            HttpContext.Current.Session.Clear();
            
            // Note: Clearing all Redis keys for a session would require tracking all keys
            // For now, rely on Redis TTL expiration
        }
    }
}
