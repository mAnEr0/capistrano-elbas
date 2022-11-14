require 'elbas'
include Elbas::Logger

namespace :elbas do
  task :ssh do
    include Capistrano::DSL

    info "SSH commands:"
    env.servers.to_a.each.with_index do |server, i|
      info "    #{i + 1}) ssh #{fetch(:user)}@#{server.hostname}"
    end
  end

  task :deploy do
    fetch(:aws_autoscale_group_names).each do |aws_autoscale_group_name|
      info "Grupo de autoescalado: #{aws_autoscale_group_name}"
      asg = Elbas::AWS::AutoscaleGroup.new aws_autoscale_group_name
      inst_count = asg.instances.count
      instance = asg.instances.running.sample

      if inst_count > 1
        info "Tenemos mas de una instancia corriendo. Pasamos la instancia #{instance.id} a standby."
        asg.enter_standby(instance.id)
      else
        info "Solo hay una instancia corriendo. Todo se hara online, puede haber interrupcion del servicio apreciable."
      end

      info "Creando AMI para la instancia seleccionada. Despues se rebotara la instancia ..."
      ami = Elbas::AWS::AMI.create instance
      ami.tag 'Name', "asg-#{asg.name}"
      ami.tag 'ELBAS-Deploy-group', asg.name
      ami.tag 'ELBAS-Deploy-id', env.timestamp.to_i.to_s
      info  "AMI creada: #{ami.id}."

      info "Actualizando el launch template con la nueva AMI ..."
      launch_template = asg.launch_template.update ami
      info "Launch template actualizado, nueva version por defecto = #{launch_template.version}"

      info "Borrando la AMI antigua..."
      ami.ancestors.each do |ancestor|
        info "AMI borrada: #{ancestor.id}"
        ancestor.delete
      end

      if inst_count > 1
        info "Intentamos poner de nuevo en servicio la instancia #{instance.id} ..."
        asg.exit_standby(instance.id)
        info "La instancia ha sido devuelta al servicio con exito."
      end

      info "Deploy completado!"
    end
  end
end
