import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import { Vpc } from "./constructs/vpc";
import { AutoScalingGroup } from "./constructs/auto-scaling-group";
import { Alb } from "./constructs/alb";
import { Route53HostedZone } from "./constructs/route53-hosted-zone";

export class WebStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // VPC
    const vpc = new Vpc(this, "Vpc");

    // EC2 Instance
    const asg = new AutoScalingGroup(this, "AutoScalingGroup", {
      vpc: vpc.vpc,
    });

    const alb = new Alb(this, "Alb", {
      vpc: vpc.vpc,
      asg: asg.asg,
    });

    new Route53HostedZone(this, "Route53HostedZone", {
      alb: alb.alb,
    });
  }
}
