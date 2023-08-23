import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as fs from "fs";
import * as path from "path";

export interface AutoScalingGroupProps {
  vpc: cdk.aws_ec2.IVpc;
}

export class AutoScalingGroup extends Construct {
  readonly asg: cdk.aws_autoscaling.AutoScalingGroup;

  constructor(scope: Construct, id: string, props: AutoScalingGroupProps) {
    super(scope, id);

    // Key pair
    const keyName = "test-key-pair";
    const keyPair = new cdk.aws_ec2.CfnKeyPair(this, "KeyPair", {
      keyName,
    });
    keyPair.applyRemovalPolicy(cdk.RemovalPolicy.DESTROY);

    // User data
    const userDataScript = fs.readFileSync(
      path.join(__dirname, "../ec2/user-data.sh"),
      "utf8"
    );
    const userData = cdk.aws_ec2.UserData.forLinux({
      shebang: "#!/bin/bash",
    });
    userData.addCommands(userDataScript);

    this.asg = new cdk.aws_autoscaling.AutoScalingGroup(this, "Asg", {
      machineImage: cdk.aws_ec2.MachineImage.lookup({
        name: "RHEL-9.2.0_HVM-20230726-x86_64-61-Hourly2-GP2",
        owners: ["309956199498"],
      }),
      instanceType: new cdk.aws_ec2.InstanceType("t3.micro"),
      blockDevices: [
        {
          deviceName: "/dev/sda1",
          volume: cdk.aws_autoscaling.BlockDeviceVolume.ebs(10, {
            volumeType: cdk.aws_autoscaling.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
      vpc: props.vpc,
      vpcSubnets: props.vpc.selectSubnets({
        subnetGroupName: "Public",
      }),
      keyName,
      maxCapacity: 3,
      minCapacity: 2,
      ssmSessionPermissions: true,
      userData,
      healthCheck: cdk.aws_autoscaling.HealthCheck.elb({
        grace: cdk.Duration.minutes(10),
      }),
    });
    this.asg.scaleOnCpuUtilization("CpuScaling", {
      targetUtilizationPercent: 50,
    });

    // Output
    // Key pair
    new cdk.CfnOutput(this, "GetSecretKeyCommand", {
      value: `aws ssm get-parameter --name /ec2/keypair/${keyPair.getAtt(
        "KeyPairId"
      )} --region ${
        cdk.Stack.of(this).region
      } --with-decryption --query Parameter.Value --output text > ./key-pair/${keyName}.pem`,
    });
  }
}
