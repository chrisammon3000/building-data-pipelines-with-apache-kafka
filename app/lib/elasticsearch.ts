import * as path from 'path';
import * as config from '../config.json';
import cdk = require('aws-cdk-lib');
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Asset } from 'aws-cdk-lib/aws-s3-assets';
import * as ssm from 'aws-cdk-lib/aws-ssm';

interface ElasticsearchProps {
    vpc: ec2.IVpc;
}

export class Ec2Elasticsearch extends Construct {
    public readonly endpointSsmParamName: string;
    constructor(scope: Construct, id: string, props: ElasticsearchProps) {
        super(scope, id);

        const vpc = props.vpc;

        // deploy an EC2 instance with Elasticsearch
        // Instance security group
        const securityGroup = new ec2.SecurityGroup(this, 'ElasticsearchSecurityGroup', {
            vpc: vpc,
            allowAllOutbound: true,
            description: 'Allow SSH (TCP port 22) in',
        });

        // Allow connections from your IP address (set in config.json)
        securityGroup.addIngressRule(
            ec2.Peer.ipv4(config.services.elasticsearch.env.ssh_cidr),
            ec2.Port.tcp(9200),
            'Allow Elasticsearch access');

        securityGroup.addIngressRule(
            ec2.Peer.ipv4(config.services.elasticsearch.env.ssh_cidr),
            ec2.Port.tcp(22),
            'Allow SSH');

        // IAM role for the instance allows SSM access
        const role = new iam.Role(this, 'Role', {
            assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
            managedPolicies: [
                iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
            ]
        });
        
        // Amazon Linux 2 2023 image
        const ami = ec2.MachineImage.latestAmazonLinux2023();
        
        // create the instance
        const instance = new ec2.Instance(this, 'Ec2ElasticsearchInstance', {
            vpc,
            instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
            machineImage: ami,
            securityGroup,
            keyName: config.services.elasticsearch.env.ssh_key_name,
            role,
            instanceName: `${config.tags.app}-elasticsearch`,
            blockDevices: [{
                deviceName: '/dev/xvda',
                volume: ec2.BlockDeviceVolume.ebs(config.services.elasticsearch.env.ebs_volume_size)
            }]
        });

        // add the user data script
        const userData = new Asset(this, 'UserData', {
            path: path.join(__dirname, '../src/config.sh')
        });

        const localPath = instance.userData.addS3DownloadCommand({
            bucket: userData.bucket,
            bucketKey: userData.s3ObjectKey
        });

        instance.userData.addExecuteFileCommand({
            filePath: localPath,
            arguments: '--verbose -y'
        });
        userData.grantRead(instance.role);

        // create an elastic IP and associate it with the instance
        const eip = new ec2.CfnEIP(this, 'EIP', {
            domain: 'vpc'
        });

        // associate the EIP with the instance
        new ec2.CfnEIPAssociation(this, 'EIPAssociation', {
            allocationId: eip.attrAllocationId,
            instanceId: instance.instanceId
        });

        // SSM parameters
        const instanceIdSsmParam = new ssm.StringParameter(this, 'InstanceId', {
            parameterName: `/${config.tags.org}/${config.tags.app}/InstanceId`,
            simpleName: false,
            stringValue: instance.instanceId
        });

        const endpointValue = `http://${eip.attrPublicIp}:8080`
        const endpointSsmParam = new ssm.StringParameter(this, 'Ec2ElasticsearchEndpointParam', {
            parameterName: `/${config.tags.org}/${config.tags.app}/Ec2ElasticsearchEndpoint`,
            simpleName: false,
            stringValue: endpointValue
        });
        this.endpointSsmParamName = endpointSsmParam.parameterName
        new cdk.CfnOutput(this, 'Ec2ElasticsearchEndpointOutput', { value: endpointValue });
    }
}