import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { SharedResources } from './shared';
import { Database } from './database';
import { Ec2OpenSearch } from './opensearch';

export class KafkaDataPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const shared = new SharedResources(this, 'SharedResources');
    const vpc = shared.vpc;

    const database = new Database(this, 'Database', {
        vpc
    });
    const ec2OpenSearch = new Ec2OpenSearch(this, 'Ec2OpenSearch', {
        vpc
    });
  }
}
