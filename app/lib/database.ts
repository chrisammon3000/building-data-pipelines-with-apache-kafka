import * as path from 'path';
import * as config from '../config.json';
import cdk = require('aws-cdk-lib');
import { Construct } from 'constructs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

interface DatabaseProps {
    vpc: ec2.IVpc;
}

export class Database extends Construct {
    constructor(scope: Construct, id: string, props: DatabaseProps) {
        super(scope, id);

        const vpc = props.vpc;

        // create securty group for mysql db and allow connections from anywhere on port 3306
        const dbSecurityGroup = new ec2.SecurityGroup(this, 'DbSecurityGroup', {
            vpc,
            description: 'Security group for MySQL database',
            allowAllOutbound: true,
        });
        dbSecurityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(3306), 'Allow connections from anywhere on port 3306');

        // // create subnet group with public access
        // const dbSubnetGroup = new rds.SubnetGroup(this, 'DbSubnetGroup', {
        //     vpc,
        //     description: 'Subnet group for MySQL database',
        //     vpcSubnets: {
        //         subnetType: ec2.SubnetType.PUBLIC,
        //     },
        // });

        // Deploy an RDS MySQL instance
        const mySqlInstance = new rds.DatabaseInstance(this, 'MySqlInstance', {
            engine: rds.DatabaseInstanceEngine.MYSQL,
            credentials: rds.Credentials.fromGeneratedSecret('admin'),
            vpc,
            vpcSubnets: {
                subnetType: ec2.SubnetType.PUBLIC,
            },
            securityGroups: [dbSecurityGroup],
            allocatedStorage: 16,
        });
    }
}