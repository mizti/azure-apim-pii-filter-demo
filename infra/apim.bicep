targetScope = 'resourceGroup'

@description('APIM service name')
param apimName string

@description('Deployment location')
param location string = resourceGroup().location

@description('Publisher email')
param publisherEmail string

@description('Publisher display name')
param publisherName string = 'APIM Presidio Demo'

@description('Public URL of demo API function app, e.g. https://func-xxx.azurewebsites.net')
param demoFunctionBaseUrl string

@description('Public URL of presidio API function app, e.g. https://func-yyy.azurewebsites.net')
param presidioFunctionBaseUrl string

@description('Tags to apply to APIM resources')
param tags object = {}

var presidioAnalyzeUrl = '${presidioFunctionBaseUrl}/api/presidio/analyze'

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

resource presidioApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'presidio-api'
  parent: apim
  properties: {
    displayName: 'Presidio API'
    path: 'presidio'
    protocols: [
      'https'
    ]
    serviceUrl: presidioFunctionBaseUrl
    subscriptionRequired: false
  }
}

resource presidioAnalyzeOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  name: 'analyze'
  parent: presidioApi
  properties: {
    displayName: 'Analyze text'
    method: 'POST'
    urlTemplate: '/analyze'
    request: {
      queryParameters: []
      headers: []
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
      }
      {
        statusCode: 400
      }
    ]
  }
}

resource presidioPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  name: 'policy'
  parent: presidioApi
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/api/presidio/analyze" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

resource demoApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'demo-api'
  parent: apim
  properties: {
    displayName: 'Demo API'
    path: 'demo'
    protocols: [
      'https'
    ]
    serviceUrl: demoFunctionBaseUrl
    subscriptionRequired: false
  }
}

resource demoProcessOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  name: 'process'
  parent: demoApi
  properties: {
    displayName: 'Process text'
    method: 'POST'
    urlTemplate: '/process'
    request: {
      queryParameters: []
      headers: []
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
      }
      {
        statusCode: 400
      }
      {
        statusCode: 502
      }
    ]
  }
}

resource presidioAnalyzeNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  name: 'presidio-analyze-url'
  parent: apim
  properties: {
    displayName: 'presidio-analyze-url'
    value: presidioAnalyzeUrl
    secret: false
  }
}

resource demoPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  name: 'policy'
  parent: demoApi
  dependsOn: [
    presidioAnalyzeNamedValue
  ]
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-variable name="requestBody" value="@(context.Request.Body.As<string>(preserveContent: true))" />
    <send-request mode="new" response-variable-name="presidioResponse" timeout="20" ignore-error="false">
      <set-url>{{presidio-analyze-url}}</set-url>
      <set-method>POST</set-method>
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@((string)context.Variables["requestBody"])</set-body>
    </send-request>
    <choose>
      <when condition="@(((IResponse)context.Variables[&quot;presidioResponse&quot;]).StatusCode != 200)">
        <return-response>
          <set-status code="502" reason="Bad Gateway" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{"status":"error","message":"Presidio API call from APIM failed."}</set-body>
        </return-response>
      </when>
      <when condition="@{ var p = (IResponse)context.Variables[&quot;presidioResponse&quot;]; var json = p.Body.As<JObject>(preserveContent: true); return (bool?)json[&quot;has_pii&quot;] == true; }">
        <return-response>
          <set-status code="400" reason="Bad Request" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{"status":"rejected","message":"PII detected by APIM policy."}</set-body>
        </return-response>
      </when>
    </choose>
    <rewrite-uri template="/api/demo/process" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

output apimGatewayUrl string = 'https://${apim.name}.azure-api.net'
output apimName string = apim.name
