using System;
using System.Web;
using Newtonsoft.Json;

namespace DBProject.Helpers
{
    /// <summary>
    /// Health check endpoint for container orchestration
    /// </summary>
    public class HealthCheckHandler : IHttpHandler
    {
        public void ProcessRequest(HttpContext context)
        {
            context.Response.ContentType = "application/json";
            
            var healthStatus = new
            {
                status = "healthy",
                timestamp = DateTime.UtcNow.ToString("o"),
                service = "Clinic Management System",
                version = "1.0.0"
            };

            string json = JsonConvert.SerializeObject(healthStatus);
            context.Response.Write(json);
            context.Response.StatusCode = 200;
        }

        public bool IsReusable
        {
            get { return true; }
        }
    }
}
