import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";

export interface AlbProps {
  vpc: cdk.aws_ec2.IVpc;
  asg: cdk.aws_autoscaling.AutoScalingGroup;
}

export class Alb extends Construct {
  readonly alb: cdk.aws_elasticloadbalancingv2.IApplicationLoadBalancer;

  constructor(scope: Construct, id: string, props: AlbProps) {
    super(scope, id);

    this.alb = new cdk.aws_elasticloadbalancingv2.ApplicationLoadBalancer(
      this,
      "Default",
      {
        vpc: props.vpc,
        internetFacing: true,
        vpcSubnets: {
          subnets: props.vpc.publicSubnets,
        },
      }
    );
    props.asg.connections.allowFrom(this.alb, cdk.aws_ec2.Port.tcp(80));

    const targetGroup =
      new cdk.aws_elasticloadbalancingv2.ApplicationTargetGroup(
        this,
        "TargetGroup",
        {
          vpc: props.vpc,
          port: 80,
          targetType: cdk.aws_elasticloadbalancingv2.TargetType.INSTANCE,
          targets: [props.asg],
        }
      );

    this.alb.addListener("Listener", {
      port: 80,
      protocol: cdk.aws_elasticloadbalancingv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });
  }
}
