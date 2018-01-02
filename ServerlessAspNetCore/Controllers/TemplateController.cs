using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using ServerlessAspNetCore.Models;

namespace ServerlessAspNetCore.Controllers
{
    [Route("api")]
    public class TemplateController : Controller
    {
        // GET api
        [HttpGet("")]
        public async Task<IActionResult> Get()
        {
            await Task.CompletedTask;
            var templates = new[]
            {
                new Template {BoolProperty = true, IntProperty = 1, StringProperty = "String1"},
                new Template {BoolProperty = false, IntProperty = 2, StringProperty = "String2"}
            };
            return Ok(templates);
        }

        // GET api/{id}
        [HttpGet("{id}")]
        public async Task<IActionResult> Get(int id)
        {
            await Task.CompletedTask;
            var template = new Template {BoolProperty = true, IntProperty = id, StringProperty = $"String{id}"};
            return Ok(template);
        }

        // POST api
        [HttpPost("")]
        public async Task<IActionResult> Post([FromBody] Template templateBody)
        {
            await Task.CompletedTask;
            return Created("uri", templateBody);
        }

        // PUT api/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Put(int id, [FromBody] Template templateBody)
        {
            await Task.CompletedTask;
            return Created("uri", templateBody);
        }

        // DELETE api/values/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            await Task.CompletedTask;
            return NoContent();
        }
    }
}
