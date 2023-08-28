import * as path from 'path';
import * as config from '../config.json';
import cdk = require('aws-cdk-lib');
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

export class SharedResources extends Construct {
    public readonly vpc: ec2.IVpc;
    constructor(scope: Construct, id: string) {
        super(scope, id);

        // uncomment to use the existing default VPC
        this.vpc = ec2.Vpc.fromLookup(this, 'VPC', {
            isDefault: true,
          });
    }
}