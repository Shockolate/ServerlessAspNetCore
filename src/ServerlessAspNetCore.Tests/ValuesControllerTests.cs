using System.IO;
using System.Threading.Tasks;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.TestUtilities;
using Newtonsoft.Json;
using NUnit.Framework;

namespace ServerlessAspNetCore.Tests
{
    [TestFixture]
    public class ValuesControllerTests
    {
        [Test]
        public async Task TestGet()
        {
            var lambdaFunction = new LambdaEntryPoint();

            var requestStr = File.ReadAllText("./SampleRequests/ValuesController-Get.json");
            var request = JsonConvert.DeserializeObject<APIGatewayProxyRequest>(requestStr);
            var context = new TestLambdaContext();
            var response = await lambdaFunction.FunctionHandlerAsync(request, context);

            Assert.AreEqual(response.StatusCode, 200);
            Assert.AreEqual("[\"value1\",\"value2\"]", response.Body);
            Assert.IsTrue(response.Headers.ContainsKey("Content-Type"));
            Assert.AreEqual("application/json; charset=utf-8", response.Headers["Content-Type"]);
        }
    }
}