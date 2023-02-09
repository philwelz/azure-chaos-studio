// ################################
// ########### Common #############
// ################################

targetScope='subscription'

param location string = deployment().location

@description('The prefix of the Managed Cluster resource')
param prefix string = 'chaos'

@description('The environment of the Managed Cluster resource e.g. stg, dev, prd or demo')
param stage string = 'demo'

@description('The prefix of the Managed Cluster resource')
param baseName string = '${prefix}-${stage}'

@description('Common tags for all resources')
param tags object = {
  env: stage
  managedBy: 'bicep'
  project: prefix
}

// ################################
// ############# RG ###############
// ################################

module rgCore './modules/rg.bicep' = {
  name: 'rg-aks-${baseName}'
  params: {
    rgName: rgName
    location: location
    tags: tags
  }
}

// ################################
// ####### Managed Identity #######
// ################################

module aksIdentity './modules/identity.bicep' = {
  name: 'aksIdentity'
  scope: resourceGroup(rgCore.name)
  params: {
    basename: baseName
    tags: tags
    location: location
  }
}

// ################################
// ############# AKS ##############
// ################################

@description('The Kubernetes Version to use for the AKS Cluster')
param kubernetes_version string = '1.24.6'

module aksCluster './modules/aks.bicep' = {
  name: 'aksCluster'
  scope: resourceGroup(rgCore.name)
  params: {
    k8sVersion: kubernetes_version
    basename: baseName
    stage: stage
    location: location
    tags: tags
    identity: {
      '${aksIdentity.outputs.identityid}' : {}
    }
  }
}

// assign Managed Identity to networkContributor role
module UaiAksNetworkContributor './modules/role.bicep' = {
  name: 'ra-uai-aks-network-contributor'
  scope: resourceGroup(rgCore.name)
  params: {
    roleDefinitionResourceId: resourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') // Network Contributer
    principalId: aksIdentity.outputs.identityprincipalId
    principalType: 'ServicePrincipal'
  }
}

// ################################
// ############ GitOps ############
// ################################

module aksGitOps './modules/gitops.bicep' = {
  name: 'aksGitOps'
  scope: resourceGroup(rgCore.name)
  params: {
    stage: stage
    aksName: aksCluster.outputs.aksName
    gitRepository: 'https://github.com/philwelz/azure-chaos-studio'
    gitBranch: 'main'
    fluxKustomizationPath: './aks/gitops/cluster/'
  }
}

// ################################
// ############ Chaos #############
// ################################

module chaosStudio './modules/chaos.bicep' = {
  name: 'aksChaos'
  scope: resourceGroup(rgCore.name)
  params: {
    location: location
    tags: tags
    aksName: aksCluster.outputs.aksName
  }
}

// assign Managed Identity to networkContributor role
module SaiPodChaosAksAdmin './modules/role.bicep' = {
  name: 'ra-sai-aks-podChaos-aksAdmin'
  scope: resourceGroup(rgCore.name)
  params: {
    roleDefinitionResourceId: resourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8') // Azure Kubernetes Service Cluster Admin Role
    principalId: chaosStudio.outputs.podChaosPrincipalId
    principalType: 'ServicePrincipal'
  }
}
